#!/bin/sh
# Test script for hare2c_meta (self-hosted Hare transpiler)
set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'
PASS=0 FAIL=0
CC=${CC:-clang}
CFLAGS="-std=c11 -Wall -Wextra -Wconversion -Wfloat-conversion -Wno-overlength-strings \
        -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality \
        -Wno-implicit-int-conversion -Wno-unused-function -Wno-unused-variable \
        -O0 -ffast-math -ffunction-sections -fdata-sections -fno-builtin"

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }

# Create temp directory for test outputs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== hare2c Building runtime ==="
$CC $CFLAGS -c lib/hare/rt.c -o "$TMPDIR/rt.o"
printf "${GREEN}Built rt.o${NC}
"
echo

echo "=== hare2c Building metacompiler ==="
python3 cmd/hare2c.py \
    cmd/hare2c/main.ha \
    cmd/hare2c/arena.ha \
    cmd/hare2c/strbuf.ha \
    cmd/hare2c/dict.ha \
    cmd/hare2c/token.ha \
    cmd/hare2c/reader.ha \
    cmd/hare2c/ast.ha \
    cmd/hare2c/parser.ha \
    cmd/hare2c/pattern.ha \
    cmd/hare2c/transform.ha \
    cmd/hare2c/rules.ha \
    -o "$TMPDIR/hare2c_meta.c"

$CC $CFLAGS -o "$TMPDIR/hare2c_meta" "$TMPDIR/hare2c_meta.c" lib/hare/rt.c
printf "${GREEN}Build successful${NC}
"
echo

run_test() {
    local name="$1"
    local input="$2"
    printf "Testing %-40s " "$name..."

    if echo "$input" | "$TMPDIR/hare2c_meta" > "$TMPDIR/test_out.c" 2>&1; then
        if $CC $CFLAGS -fsyntax-only "$TMPDIR/test_out.c"; then
            pass
        else
            fail "C syntax error"
        fi
    else
        fail "transpile error"
    fi
}

run_test_parse_only() {
    local name="$1"
    local input="$2"
    printf "Testing %-40s " "$name (parse only)..."

    if echo "$input" | "$TMPDIR/hare2c_meta" > "$TMPDIR/test_out.c" 2>&1; then
        pass
    else
        fail "parse error"
    fi
}

run_file_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name..."

    local c="$TMPDIR/${name}.c"
    local o="$TMPDIR/${name}.o"
    local bin="$TMPDIR/${name}"

    if ! cat "$file" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        fail "compile error"
        return
    fi

    if ! $CC $CFLAGS "$o" "$TMPDIR/rt.o" -o "$bin"; then
        fail "link error"
        return
    fi

    if ! timeout 5 "$bin" >/dev/null 2>&1; then
        fail "runtime error"
        return
    fi

    pass
}

run_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (should fail)..."

    # Sanitize name for file path (replace / with _)
    local safe_name=$(echo "$name" | tr '/' '_')
    local c="$TMPDIR/${safe_name}.c"
    local o="$TMPDIR/${safe_name}.o"

    if ! cat "$file" | "$TMPDIR/hare2c_meta" > "$c" 2> /dev/null; then
        pass
        return
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        pass
        return
    fi

    fail "should have failed"
}

run_runtime_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (runtime fail)..."

    local c="$TMPDIR/${name}.c"
    local o="$TMPDIR/${name}.o"
    local bin="$TMPDIR/${name}"

    if ! cat "$file" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        fail "compile error"
        return
    fi

    if ! $CC $CFLAGS "$o" "$TMPDIR/rt.o" -o "$bin"; then
        fail "link error"
        return
    fi

    if "$bin" >/dev/null 2>&1; then
        fail "should have aborted"
    else
        pass
    fi
}

echo "=== hare2c Inline Tests ===" && echo

run_test "basic function" '
export fn add(a: int, b: int) int = {
    return a + b;
};
'

run_test "type cast" '
export fn cast_test(x: int) i64 = {
    return x: i64;
};
'

run_test "struct typedef" '
type point = struct {
    x: int,
    y: int,
};

export fn get_x(p: *point) int = {
    return (*p).x;
};
'

run_test "def constant" '
def MAX_SIZE: size = 100;

export fn get_max() size = {
    return MAX_SIZE;
};
'

run_test "unbounded array" '
export fn get_element(arr: *[*]int, i: size) int = {
    return arr[i];
};
'

run_test "for loop" '
export fn sum(n: int) int = {
    let total = 0;
    for (let i = 0; i < n; i += 1) {
        total += i;
    };
    return total;
};
'

run_test "if expression" '
export fn max(a: int, b: int) int = {
    if (a > b) {
        return a;
    } else {
        return b;
    };
};
'

run_test "binary operators" '
export fn ops(a: int, b: int) int = {
    let x = a + b;
    let y = a - b;
    let z = a * b;
    let w = a / b;
    let m = a % b;
    return x + y + z + w + m;
};
'

run_test "unary operators" '
export fn unary(x: int, p: *int) int = {
    let a = -x;
    let b = !x;
    let c = *p;
    let d = &x;
    return a + b + c + *d;
};
'

run_test "pointer types" '
export fn ptr_test(p: *int) void = {
    *p = 42;
    return;
};
'

run_test "use statement" '
use rt;

export fn main() void = {
    return;
};
'

run_test "boolean literals" '
export fn bool_test() bool = {
    let a = true;
    let b = false;
    if (b) { return b; };
    return a;
};
'

run_test "null literal" '
export fn null_test() *int = {
    return null;
};
'

run_test "nested field access" '
type inner = struct {
    val: int,
};

type outer = struct {
    in: inner,
};

export fn get_val(o: *outer) int = {
    return (*o).in.val;
};
'

run_test "multiple functions" '
fn helper(x: int) int = {
    return x * 2;
};

export fn main_fn(x: int) int = {
    return helper(x) + 1;
};
'

run_test "static let" '
export fn counter() int = {
    static let count: int = 0;
    count += 1;
    return count;
};
'

run_test "slice expression" '
type myslice = struct {
    data: *int,
    len: size,
    cap: size,
};

export fn slice_test(s: myslice, start: size) size = {
    return s.len + start;
};
'

run_test "break continue" '
export fn loop_ctrl() int = {
    let x = 0;
    for (let i = 0; i < 10; i += 1) {
        if (i == 5) {
            break;
        };
        if (i == 2) {
            continue;
        };
        x += i;
    };
    return x;
};
'

run_test "switch statement" '
export fn grade(x: int) int = {
    switch (x) {
    case 1 => 10;
    };
};
'

run_test "switch with block" '
export fn classify(x: int) int = {
    let result = 0;
    switch (x) {
    case 0 => {
        result = 1;
    };
    case 1, 2 => {
        result = 2;
    };
    case => {
        result = 3;
    };
    };
    return result;
};
'

run_test "yield parsing" '
export fn test_yield() void = {
    yield;
    return;
};
'

run_test "match parsing" '
type maybe_int = (int | void);

export fn test_match(r: maybe_int) int = {
    match (r) {
    case int => 1;
    case void => 0;
    };
};
'

run_test "match with block" '
type maybe_val = (int | void);

export fn handle(r: maybe_val) int = {
    let result = 0;
    match (r) {
    case int => {
        result = 1;
    };
    case void => {
        result = -1;
    };
    };
    return result;
};
'

run_test "match default only" '
type any_type = (int | void);

export fn fallback(x: any_type) int = {
    match (x) {
    case => 42;
    };
};
'

run_test "foreach value" '
type myslice = struct { data: *int, len: size, cap: size };
export fn test() int = {
    static let arr: [5]int = [1, 2, 3, 4, 5];
    let items: myslice = myslice { data = &arr[0], len = 5z, cap = 5z };
    let total = 0;
    for (let x .. items) {
        total = total + x;
    };
    return total;
};
'

run_test "foreach reference" '
type myslice = struct { data: *int, len: size, cap: size };
export fn test() void = {
    static let arr: [3]int = [10, 20, 30];
    let items: myslice = myslice { data = &arr[0], len = 3z, cap = 3z };
    for (let ptr &.. items) {
        *ptr = *ptr * 2;
    };
};
'

run_test "expression function" '
fn max(a: int, b: int) int = if (a > b) a else b;

fn min(a: int, b: int) int = if (a < b) a else b;

export fn test() int = {
    return max(10, 5) + min(3, 7);
};
'

run_test_parse_only "foreach iterator" '
// Test the for => pattern parses correctly
fn get_iter() int = {
    return 0;
};

export fn test() int = {
    let total = 0;
    for (let x => get_iter()) {
        total = total + x;
    };
    return total;
};
'

run_test "@init attribute" '
@init fn setup() void = {
    return;
};

export fn main() void = {
    return;
};
'

run_test "@fini attribute" '
@fini fn cleanup() void = {
    return;
};

export fn main() void = {
    return;
};
'

run_test "@test attribute" '
@test fn my_test() void = {
    return;
};

export fn main() void = {
    return;
};
'

run_test "@symbol attribute" '
@symbol("custom_name") fn real_name() void = {
    return;
};

export fn main() void = {
    return;
};
'

run_test "multiple attributes" '
export @init fn init_exported() void = {
    return;
};

export fn main() void = {
    return;
};
'

run_test "defer on error propagation" '
use rt;

let cleanup_count: int = 0;

fn cleanup() void = {
    cleanup_count += 1;
};

type myerror = !void;
type result = (void | myerror);

fn always_fail() result = {
    return myerror;
};

fn test_prop_with_defer() result = {
    defer cleanup();
    always_fail()?;
    return void;
};

export fn main() void = {
    cleanup_count = 0;
    test_prop_with_defer();
    return;
};
'

echo && echo "=== hare2c Examples Tests ===" && echo

for ha in test/hare/*.ha; do
    name=$(basename "$ha" .ha)
    case "$name" in pkg_*) continue;; esac

    printf "Testing %-40s " "$name..."

    c="$TMPDIR/${name}.c"
    o="$TMPDIR/${name}.o"
    bin="$TMPDIR/${name}"

    if ! cat "$ha" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        fail "transpile error"
        continue
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        fail "compile error"
        continue
    fi

    if ! $CC $CFLAGS "$o" "$TMPDIR/rt.o" -o "$bin"; then
        fail "link error"
        continue
    fi

    if ! timeout 5 "$bin" >/dev/null 2>&1; then
        fail "runtime error"
        continue
    fi

    pass
done

echo && echo "=== hare2c Hare Fail Tests ===" && echo

for f in test/hare/fail/harebad_*.ha; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.ha}")
    # Remove "harebad_" prefix for display
    display_name="${basename_name#harebad_}"

    run_fail_test "hare/$display_name" "$f"
done

echo && echo "=== hare2c Hare/Pika Success Tests ===" && echo

for f in test/pika/*.pka; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.pka}")
    # Skip pika-prefixed tests (pika2c-only features)
    case "$basename_name" in pika_*) continue;; esac
    name="pika_${basename_name}"
    printf "Testing %-40s " "pika/$basename_name..."

    c="$TMPDIR/${name}.c"
    o="$TMPDIR/${name}.o"
    bin="$TMPDIR/${name}"

    if ! cat "$f" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        fail "transpile error"
        continue
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        fail "compile error"
        continue
    fi

    if ! $CC $CFLAGS "$o" "$TMPDIR/rt.o" -o "$bin"; then
        fail "link error"
        continue
    fi

    if ! timeout 5 "$bin" >/dev/null 2>&1; then
        fail "runtime error"
        continue
    fi

    pass
done

echo && echo "=== hare2c Hare/Pika Compile-Time Fail Tests ===" && echo

for f in test/pika/fail/*.pka; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.pka}")
    case "$basename_name" in runtime_*) continue;; esac
    # Skip pika-specific tests
    case "$basename_name" in *pika*) continue;; esac
    name="pika_fail_${basename_name}"
    printf "Testing %-40s " "pika/$basename_name (should fail)..."

    c="$TMPDIR/${name}.c"
    o="$TMPDIR/${name}.o"

    if ! cat "$f" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        pass
        continue
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        pass
        continue
    fi

    fail "should have failed"
done

echo && echo "=== hare2c Hare/Pika Runtime Fail Tests ===" && echo

for f in test/pika/fail/runtime_*.pka; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.pka}")
    name="pika_fail_${basename_name}"
    printf "Testing %-40s " "pika/$basename_name (runtime fail)..."

    c="$TMPDIR/${name}.c"
    o="$TMPDIR/${name}.o"
    bin="$TMPDIR/${name}"

    if ! cat "$f" | "$TMPDIR/hare2c_meta" > "$c" 2>&1; then
        fail "transpile error"
        continue
    fi

    if ! $CC $CFLAGS -c "$c" -o "$o"; then
        fail "compile error"
        continue
    fi

    if ! $CC $CFLAGS "$o" "$TMPDIR/rt.o" -o "$bin"; then
        fail "link error"
        continue
    fi

    if "$bin" >/dev/null 2>&1; then
        fail "should have aborted"
    else
        pass
    fi
done

echo && echo "=== hare2c Self-Hosting Tests ===" && echo

HARE_FILES="cmd/hare2c/arena.ha cmd/hare2c/ast.ha cmd/hare2c/dict.ha cmd/hare2c/pattern.ha cmd/hare2c/strbuf.ha cmd/hare2c/token.ha cmd/hare2c/reader.ha cmd/hare2c/parser.ha cmd/hare2c/transform.ha cmd/hare2c/rules.ha cmd/hare2c/main.ha"

printf "Testing %-40s " "gen1 (meta transpiles itself)..."
if cat $HARE_FILES | "$TMPDIR/hare2c_meta" > "$TMPDIR/gen1.c" 2>&1; then
    if $CC $CFLAGS "$TMPDIR/gen1.c" "$TMPDIR/rt.o" -o "$TMPDIR/gen1"; then
        pass
    else
        fail "compile error"
    fi
else
    fail "transpile error"
fi

printf "Testing %-40s " "gen2 (gen1 transpiles itself)..."
if [ -f "$TMPDIR/gen1" ]; then
    if cat $HARE_FILES | "$TMPDIR/gen1" > "$TMPDIR/gen2.c" 2>&1; then
        if $CC $CFLAGS "$TMPDIR/gen2.c" "$TMPDIR/rt.o" -o "$TMPDIR/gen2"; then
            pass
        else
            fail "compile error"
        fi
    else
        fail "transpile error"
    fi
else
    fail "gen1 not built"
fi

printf "Testing %-40s " "gen3 (gen2 transpiles itself)..."
if [ -f "$TMPDIR/gen2" ]; then
    if cat $HARE_FILES | "$TMPDIR/gen2" > "$TMPDIR/gen3.c" 2>&1; then
        if $CC $CFLAGS "$TMPDIR/gen3.c" "$TMPDIR/rt.o" -o "$TMPDIR/gen3"; then
            pass
        else
            fail "compile error"
        fi
    else
        fail "transpile error"
    fi
else
    fail "gen2 not built"
fi

echo && echo "=== hare2c Pika2C Compilation Test ===" && echo

# Test compiling pika2c source with hare2c metacompiler
PIKA_FILES="cmd/pika2c/*.pka"

printf "Testing %-40s " "pika2c (hare2c transpiles pika2c)..."
if cat $PIKA_FILES | "$TMPDIR/hare2c_meta" > "$TMPDIR/pikah2c.c"; then
    if $CC $CFLAGS -c "$TMPDIR/pikah2c.c" -o "$TMPDIR/pikah2c.o" 2>/dev/null; then
        if $CC $CFLAGS "$TMPDIR/pikah2c.o" "$TMPDIR/rt.o" -o "$TMPDIR/pikah2c" 2>/dev/null; then
            pass
        else
            fail "link error"
        fi
    else
        fail "compile error"
    fi
else
    fail "transpile error"
fi

echo && echo "=== hare2c Fixed-Point Test ===" && echo

printf "Testing %-40s " "fixed-point (gen2 == gen3 output)..."
if [ -f "$TMPDIR/gen2.c" ] && [ -f "$TMPDIR/gen3.c" ]; then
    if diff -q "$TMPDIR/gen2.c" "$TMPDIR/gen3.c" > /dev/null 2>&1; then
        pass
    else
        echo
        echo "  Output differs! First differences:"
        diff "$TMPDIR/gen2.c" "$TMPDIR/gen3.c" | head -20
        fail "output differs"
    fi
else
    fail "missing gen2.c or gen3.c"
fi

printf "Testing %-40s " "binary equivalence (gen2 == gen3)..."
if [ -f "$TMPDIR/gen2" ] && [ -f "$TMPDIR/gen3" ]; then
    if cat $HARE_FILES | "$TMPDIR/gen2" > "$TMPDIR/test_gen2.c" && \
       cat $HARE_FILES | "$TMPDIR/gen3" > "$TMPDIR/test_gen3.c"; then
        if diff -q "$TMPDIR/test_gen2.c" "$TMPDIR/test_gen3.c" > /dev/null 2>&1; then
            pass
        else
            fail "binaries produce different output"
        fi
    else
        fail "transpile error"
    fi
else
    fail "missing gen2 or gen3"
fi

echo && echo "=== hare2c Summary ==="
TOTAL=$((PASS + FAIL))
printf "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Total: $TOTAL
"

[ $FAIL -eq 0 ] && printf "${GREEN}All tests passed!${NC}
" && exit 0
printf "${RED}Some tests failed.${NC}
" && exit 1
