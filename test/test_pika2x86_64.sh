#!/bin/sh
# Test script for pika2c x86_64 backend

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'
PASS=0 FAIL=0 SKIP=0
CC=${CC:-clang}
CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-unused-function -Wno-unused-variable -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality -O0 -ffast-math -march=native -mtune=native -fno-builtin"
ASM_LDFLAGS="-nostdlib -static -fno-pie"

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }
skip() { printf "${YELLOW}SKIP${NC} ($1)\n"; SKIP=$((SKIP + 1)); }

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Building pika2c ==="
python3 cmd/hare2c.py -p pika \
    cmd/pika2c/*.pka \
    -o "$TMPDIR/pika2c.c" || exit 1

$CC $CFLAGS "$TMPDIR/pika2c.c" lib/pika/rt_cstd.c -o "$TMPDIR/pika2c"
printf "${GREEN}Build successful${NC}\n"
echo

run_x86_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (x86_64)..."

    local sfile="$TMPDIR/${name}.s"
    local binfile="$TMPDIR/${name}.bin"

    if ! { printf '%s\n' '-T x86_64'; cat "$file"; } | "$TMPDIR/pika2c" > "$sfile"; then
        fail "transpile error"
        return
    fi

    if ! $CC $ASM_LDFLAGS "$sfile" lib/pika/rt.c -o "$binfile"; then
        fail "assemble/link error"
        return
    fi

    if ! timeout 5 "$binfile" >/dev/null 2>&1; then
        fail "runtime error"
        return
    fi
    pass
}

run_x86_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (x86_64 should fail)..."

    if { printf '%s\n' '-T x86_64'; cat "$file"; } | "$TMPDIR/pika2c" > /dev/null 2>&1; then
        fail "should have failed"
    else
        pass
    fi
}

run_x86_runtime_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (x86_64 runtime fail)..."

    local sfile="$TMPDIR/${name}.s"
    local binfile="$TMPDIR/${name}.bin"

    if ! { printf '%s\n' '-T x86_64'; cat "$file"; } | "$TMPDIR/pika2c" > "$sfile"; then
        fail "transpile error"
        return
    fi

    if ! $CC $ASM_LDFLAGS "$sfile" lib/pika/rt.c -o "$binfile"; then
        fail "assemble/link error"
        return
    fi

    if "$binfile" 2>/dev/null; then
        fail "should have aborted"
    else
        pass
    fi
}

run_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (C should fail)..."

    local cfile="$TMPDIR/${name}.c"

    # First check: does pika2c reject it?
    if ! "$TMPDIR/pika2c" < "$file" > "$cfile"; then
        pass; return
    fi

    # Second check: does C compiler reject it with strict flags?
    local STRICT_CFLAGS="-std=c11 -Werror -Wall -Wextra -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-gnu-auto-type -Wno-unused-function -Wno-unused-variable -Wno-gnu-statement-expression -Wno-parentheses-equality"
    if ! $CC $STRICT_CFLAGS "$cfile" lib/pika/rt.c -o "$TMPDIR/${name}.bin" 2>/dev/null; then
        pass; return
    fi

    fail "should have failed"
}

echo "=== pika2c  x86_64 Success Tests (test/pika) ===" && echo
for f in test/pika/*.pka; do
    [ -f "$f" ] && run_x86_test "$(basename ${f%.pka})" "$f"
done

echo && echo "=== pika2c  x86_64 Compile-Time Fail Tests (test/pika/fail) ===" && echo
for f in test/pika/fail/*.pka; do
    if [ -f "$f" ]; then
        case "$(basename "$f")" in runtime_*) continue;; esac
        run_fail_test "$(basename ${f%.pka})" "$f"
    fi
done

echo && echo "=== pika2c  x86_64 Runtime Fail Tests (test/pika/fail) ===" && echo
for f in test/pika/fail/runtime_*.pka; do
    [ -f "$f" ] && run_x86_runtime_test "$(basename ${f%.pka})" "$f"
done

echo && echo "=== pika2c  x86_64 Backend-Specific Tests ===" && echo
for f in test/x86_64/001_main_arith.pka \
         test/x86_64/003_control_flow.pka test/x86_64/004_float_ops.pka \
         test/x86_64/005_vector_smoke.pka test/x86_64/006_vector_reuse.pka \
         test/x86_64/007_vector_reuse_chain.pka test/x86_64/008_vector_pack_final.pka \
         test/x86_64/009_matrix_mul_unrolled.pka \
         test/x86_64/015_tagged_sret_param.pka \
         test/x86_64/016_struct_return_small.pka \
         test/x86_64/017_struct_return_large.pka \
         test/x86_64/200_structs_basic.pka test/x86_64/210_arrays_loop.pka \
         test/x86_64/220_if_else_basic.pka test/x86_64/230_for_sum.pka \
         test/x86_64/240_for_break_continue.pka test/x86_64/250_else_if_chain.pka \
         test/x86_64/260_while_style.pka test/x86_64/270_nested_loops.pka \
         test/x86_64/280_nested_loops_arrays.pka test/x86_64/300_array_fill_basic.pka \
         test/x86_64/310_runtime_calls.pka test/x86_64/311_symbol_interop.pka \
         test/x86_64/312_rt_write_output.pka \
         test/x86_64/320_slices_basic.pka test/x86_64/330_strings_basic.pka \
         test/x86_64/331_string_escapes.pka test/x86_64/340_match_nullable_expr.pka \
         test/x86_64/400_tagged_basic.pka test/x86_64/410_void_alias_tagged.pka \
         test/x86_64/420_nullable_match_narrowing.pka test/x86_64/430_globals_static_basic.pka \
         test/x86_64/440_arena_smoke.pka test/x86_64/450_structs_globals.pka \
         test/x86_64/600_defaults_casts.pka test/x86_64/610_globals_static_arrays.pka \
         test/x86_64/620_autoderef_nested.pka test/x86_64/700_local_arr_def_size.pka; do
    [ -f "$f" ] && run_x86_test "$(basename ${f%.pka})" "$f"
done

run_x86_runtime_test "002_runtime_assert_fail" "test/x86_64/002_runtime_assert_fail.pka"
run_x86_runtime_test "211_array_bounds_fail" "test/x86_64/211_array_bounds_fail.pka"

echo && echo "=== pika2c  x86_64 Self-Hosting (gen ladder) ===" && echo

PIKA_FILES="cmd/pika2c/*.pka"

printf "Testing %-40s " "gen1 (gen0 -> asm)..."
GEN1_BIN="$TMPDIR/gen1"
GEN1_S="$TMPDIR/gen1.s"
if { printf '%s\n' '-T x86_64'; cat $PIKA_FILES; } | "$TMPDIR/pika2c" > "$GEN1_S" 2>&1; then
    if $CC $ASM_LDFLAGS "$GEN1_S" lib/pika/rt.c -o "$GEN1_BIN" 2>&1; then pass
    else fail "compile error"; fi
else fail "transpile error"; fi

printf "Testing %-40s " "gen2 (gen1 -> asm)..."
GEN2_BIN="$TMPDIR/gen2"
GEN2_S="$TMPDIR/gen2.s"
if [ -x "$GEN1_BIN" ]; then
    if { printf '%s\n' '-T x86_64'; cat $PIKA_FILES; } | "$GEN1_BIN" > "$GEN2_S" 2>&1; then
        if $CC $ASM_LDFLAGS "$GEN2_S" lib/pika/rt.c -o "$GEN2_BIN" 2>&1; then pass
        else fail "compile error"; fi
    else fail "transpile error"; fi
else fail "gen1 not built"; fi

printf "Testing %-40s " "gen3 (gen2 -> asm)..."
GEN3_BIN="$TMPDIR/gen3"
GEN3_S="$TMPDIR/gen3.s"
if [ -x "$GEN2_BIN" ]; then
    if { printf '%s\n' '-T x86_64'; cat $PIKA_FILES; } | "$GEN2_BIN" > "$GEN3_S" 2>&1; then
        if $CC $ASM_LDFLAGS "$GEN3_S" lib/pika/rt.c -o "$GEN3_BIN" 2>&1; then pass
        else fail "compile error"; fi
    else fail "transpile error"; fi
else fail "gen2 not built"; fi

echo && echo "=== pika2c  x86_64 Fixed-Point (asm) ===" && echo
printf "Testing %-40s " "gen2.s == gen3.s..."
if [ -f "$GEN2_S" ] && [ -f "$GEN3_S" ]; then
    if diff -q "$GEN2_S" "$GEN3_S" >/dev/null 2>&1; then pass
    else fail "assembly differs"; fi
else fail "missing gen2/gen3 asm"; fi

echo && echo "=== pika2c  x86_64 Summary ==="
TOTAL=$((PASS + FAIL))
printf "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Total: $TOTAL\n"

if [ $FAIL -eq 0 ]; then
    printf "${GREEN}All tests passed!${NC}\n"
    exit 0
fi
printf "${RED}Some tests failed.${NC}\n"
exit 1
