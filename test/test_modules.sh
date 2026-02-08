#!/bin/sh
# test_modules.sh - Test -H header generation for cross-module pika compilation

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m' GREEN='\033[0;32m' NC='\033[0m'
PASS=0 FAIL=0
CC=${CC:-gcc}
CFLAGS="-std=c11 -O0 -fno-builtin -Wno-overlength-strings -Wno-unused-function -Wno-unused-variable"

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Building pika2c ==="
python3 cmd/hare2c.py -p pika cmd/pika2c/*.pka -o "$TMPDIR/pika2c.c" || exit 1
$CC $CFLAGS "$TMPDIR/pika2c.c" lib/pika/rt_cstd.c -o "$TMPDIR/pika2c"
printf "${GREEN}Build successful${NC}\n"
echo
PIKA2C="$TMPDIR/pika2c"

# ============================================================================
# Test 1: Header generation content validation
# ============================================================================
echo "=== Header Generation Tests ==="
echo

# Create library module
cat > "$TMPDIR/mylib.pka" << 'MODEOF'
use rt;

export type Point = struct {
	x: i32,
	y: i32,
};

export def MAX_VAL: i32 = 1000;

export @symbol("mylib_calc") fn compute_sum(a: i32, b: i32) i32 = {
	return a + b;
};

export fn add_default(a: i32, b: i32 = 10) i32 = {
	return a + b;
};

export fn make_point(x: i32, y: i32) Point = {
	return Point { x = x, y = y };
};

fn internal_helper() i32 = {
	return 42;
};
MODEOF

printf "Testing %-50s " "header contains @symbol declarations..."
(printf '%s\n' "-H" "-N mylib"; cat "$TMPDIR/mylib.pka") | "$PIKA2C" > "$TMPDIR/mylib_header.pka"
if grep -q '@symbol("mylib_calc") fn mylib_compute_sum' "$TMPDIR/mylib_header.pka"; then
	pass
else
	fail "missing @symbol for compute_sum"
fi

printf "Testing %-50s " "header contains non-symbol exported fns..."
if grep -q '@symbol("mylib_add_default") fn mylib_add_default' "$TMPDIR/mylib_header.pka"; then
	pass
else
	fail "missing add_default declaration"
fi

printf "Testing %-50s " "header contains default arg values..."
if grep -q 'b: i32 = 10' "$TMPDIR/mylib_header.pka"; then
	pass
else
	fail "missing default arg"
fi

printf "Testing %-50s " "header contains exported type..."
if grep -q 'type mylib_Point = struct' "$TMPDIR/mylib_header.pka"; then
	pass
else
	fail "missing type declaration"
fi

printf "Testing %-50s " "header contains exported def..."
if grep -q 'def mylib_MAX_VAL' "$TMPDIR/mylib_header.pka"; then
	pass
else
	fail "missing def declaration"
fi

printf "Testing %-50s " "header excludes non-exported functions..."
if grep -q 'internal_helper' "$TMPDIR/mylib_header.pka"; then
	fail "internal function leaked into header"
else
	pass
fi

printf "Testing %-50s " "header excludes main function..."
if grep -q 'fn mylib_main' "$TMPDIR/mylib_header.pka"; then
	fail "main function leaked into header"
else
	pass
fi

# ============================================================================
# Test 2: Cross-module compilation with @symbol resolution
# ============================================================================
echo
echo "=== Cross-Module Compilation Tests ==="
echo

cat > "$TMPDIR/consumer.pka" << 'CONEOF'
use rt;
use mylib;

export fn main() void = {
	// Test @symbol function
	let sum = mylib::compute_sum(3, 4);
	assert(sum == 7);

	// Test function with default arg - both forms
	let r1 = mylib::add_default(5, 20);
	assert(r1 == 25);
	let r2 = mylib::add_default(5);
	assert(r2 == 15);

	// Test exported type via return value
	let p = mylib::make_point(10, 20);
	assert(p.x == 10);
	assert(p.y == 20);

	// Test exported def
	assert(mylib::MAX_VAL == 1000);
};
CONEOF

printf "Testing %-50s " "cross-module compile (lib + consumer)..."

# Compile library with -N
(printf '%s\n' "-N mylib"; cat "$TMPDIR/mylib.pka") | "$PIKA2C" > "$TMPDIR/mylib.c" 2>/dev/null

# Compile consumer with header prepended
(cat "$TMPDIR/mylib_header.pka"; cat "$TMPDIR/consumer.pka") | "$PIKA2C" > "$TMPDIR/consumer.c" 2>/dev/null

# Concatenate C outputs, compile, and link
if ! cat "$TMPDIR/mylib.c" "$TMPDIR/consumer.c" | $CC $CFLAGS -x c - lib/pika/rt.c -o "$TMPDIR/test_mod" 2>"$TMPDIR/compile_err.txt"; then
	fail "compile error"
	cat "$TMPDIR/compile_err.txt"
elif ! timeout 5 "$TMPDIR/test_mod" >/dev/null 2>&1; then
	fail "runtime error"
else
	pass
fi

# ============================================================================
# Test 3: Multiple modules
# ============================================================================

cat > "$TMPDIR/mathlib.pka" << 'MATHEOF'
use rt;

export fn multiply(a: i32, b: i32) i32 = {
	return a * b;
};

export fn square(x: i32) i32 = {
	return x * x;
};
MATHEOF

cat > "$TMPDIR/multi_consumer.pka" << 'MULTIEOF'
use rt;
use mylib;
use mathlib;

export fn main() void = {
	// Use mylib functions
	let sum = mylib::compute_sum(3, 4);
	assert(sum == 7);
	let p = mylib::make_point(5, 6);
	assert(p.x == 5);

	// Use mathlib functions
	let prod = mathlib::multiply(3, 4);
	assert(prod == 12);
	let sq = mathlib::square(7);
	assert(sq == 49);

	// Cross-module expression
	let combined = mylib::add_default(mathlib::square(3));
	assert(combined == 19);
};
MULTIEOF

printf "Testing %-50s " "multi-module compile (2 libs + consumer)..."

# Generate mathlib header
(printf '%s\n' "-H" "-N mathlib"; cat "$TMPDIR/mathlib.pka") | "$PIKA2C" > "$TMPDIR/mathlib_header.pka"

# Compile mathlib with -N
(printf '%s\n' "-N mathlib"; cat "$TMPDIR/mathlib.pka") | "$PIKA2C" > "$TMPDIR/mathlib.c" 2>/dev/null

# Compile consumer with both headers
(cat "$TMPDIR/mylib_header.pka"; cat "$TMPDIR/mathlib_header.pka"; cat "$TMPDIR/multi_consumer.pka") | "$PIKA2C" > "$TMPDIR/multi_consumer.c" 2>/dev/null

# Compile and link
if ! cat "$TMPDIR/mylib.c" "$TMPDIR/mathlib.c" "$TMPDIR/multi_consumer.c" | $CC $CFLAGS -x c - lib/pika/rt.c -o "$TMPDIR/test_multi" 2>"$TMPDIR/multi_err.txt"; then
	fail "compile error"
	cat "$TMPDIR/multi_err.txt"
elif ! timeout 5 "$TMPDIR/test_multi" >/dev/null 2>&1; then
	fail "runtime error"
else
	pass
fi

# ============================================================================
# Test 4: Enum and complex types in headers
# ============================================================================

cat > "$TMPDIR/enumlib.pka" << 'ENUMEOF'
use rt;

export type Color = enum u8 {
	RED = 0,
	GREEN = 1,
	BLUE = 2,
};

export fn color_value(c: Color) u8 = {
	return c: u8;
};

export fn get_red() Color = {
	return Color::RED;
};

export fn get_green() Color = {
	return Color::GREEN;
};
ENUMEOF

cat > "$TMPDIR/enum_consumer.pka" << 'ECEOF'
use rt;
use enumlib;

export fn main() void = {
	let r = enumlib::get_red();
	assert(enumlib::color_value(r) == 0: u8);
	let g = enumlib::get_green();
	assert(enumlib::color_value(g) == 1: u8);
};
ECEOF

printf "Testing %-50s " "enum type in module header..."

(printf '%s\n' "-H" "-N enumlib"; cat "$TMPDIR/enumlib.pka") | "$PIKA2C" > "$TMPDIR/enumlib_header.pka"
(printf '%s\n' "-N enumlib"; cat "$TMPDIR/enumlib.pka") | "$PIKA2C" > "$TMPDIR/enumlib.c" 2>/dev/null
(cat "$TMPDIR/enumlib_header.pka"; cat "$TMPDIR/enum_consumer.pka") | "$PIKA2C" > "$TMPDIR/enum_consumer.c" 2>/dev/null

if ! cat "$TMPDIR/enumlib.c" "$TMPDIR/enum_consumer.c" | $CC $CFLAGS -x c - lib/pika/rt.c -o "$TMPDIR/test_enum" 2>"$TMPDIR/enum_err.txt"; then
	fail "compile error"
	cat "$TMPDIR/enum_err.txt"
elif ! timeout 5 "$TMPDIR/test_enum" >/dev/null 2>&1; then
	fail "runtime error"
else
	pass
fi

# ============================================================================
# Test 5: Exported extern functions in headers
# ============================================================================

cat > "$TMPDIR/extlib.pka" << 'EXTEOF'
use rt;

export @symbol("extlib_get_pid") fn get_pid() i32;

export fn double_it(x: i32) i32 = {
	return x * 2;
};
EXTEOF

printf "Testing %-50s " "header contains exported extern fn..."
(printf '%s\n' "-H" "-N extlib"; cat "$TMPDIR/extlib.pka") | "$PIKA2C" > "$TMPDIR/extlib_header.pka"
if grep -q '@symbol("extlib_get_pid") fn extlib_get_pid' "$TMPDIR/extlib_header.pka"; then
	pass
else
	fail "missing extern fn in header"
fi

printf "Testing %-50s " "extern fn cross-module compile..."

cat > "$TMPDIR/ext_consumer.pka" << 'EXCEOF'
use rt;
use extlib;

export fn main() void = {
	let d = extlib::double_it(5);
	assert(d == 10);
};
EXCEOF

# Compile library with -N
(printf '%s\n' "-N extlib"; cat "$TMPDIR/extlib.pka") | "$PIKA2C" > "$TMPDIR/extlib.c" 2>/dev/null

# Compile consumer with header
(cat "$TMPDIR/extlib_header.pka"; cat "$TMPDIR/ext_consumer.pka") | "$PIKA2C" > "$TMPDIR/ext_consumer.c" 2>/dev/null

if ! cat "$TMPDIR/extlib.c" "$TMPDIR/ext_consumer.c" | $CC $CFLAGS -x c - lib/pika/rt.c -o "$TMPDIR/test_ext" 2>"$TMPDIR/ext_err.txt"; then
	fail "compile error"
	cat "$TMPDIR/ext_err.txt"
elif ! timeout 5 "$TMPDIR/test_ext" >/dev/null 2>&1; then
	fail "runtime error"
else
	pass
fi

# ============================================================================
# Summary
# ============================================================================
echo
echo "=== Module Tests Summary ==="
TOTAL=$((PASS + FAIL))
printf "Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}  Total: %d\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
	printf "${RED}Some tests failed.${NC}\n"
	exit 1
fi
printf "${GREEN}All tests passed!${NC}\n"
