#!/bin/sh
# Test script for pika2c (self-hosted pika transpiler)

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'
PASS=0 FAIL=0 SKIP=0
CC=${CC:-clang}
CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-unused-function -Wno-unused-variable -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality -O0 -ffast-math -march=native -mtune=native -fno-builtin"

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }
skip() { printf "${YELLOW}SKIP${NC} ($1)\n"; SKIP=$((SKIP + 1)); }

# Create temp directory for test outputs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Building pika2c ==="
	python3 cmd/hare2c.py -p pika \
	    cmd/pika2c/*.pka \
	    -o "$TMPDIR/pika2c.c" || exit 1

$CC $CFLAGS "$TMPDIR/pika2c.c" lib/pika/rt_cstd.c -o "$TMPDIR/pika2c"
printf "${GREEN}Build successful${NC}\n"
echo

run_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name..."

    local cfile="$TMPDIR/${name}.c"
    local bin="$TMPDIR/${name}"

    if ! "$TMPDIR/pika2c" < "$file" > "$cfile"; then
        fail "transpile error"; return
    fi
    if ! $CC $CFLAGS "$cfile" lib/pika/rt.c -o "$bin"; then
        fail "compile error"; return
    fi
    if ! timeout 5 "$bin" >/dev/null 2>&1; then
        fail "runtime error"; return
    fi
    pass
}

run_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (should fail)..."

    local cfile="$TMPDIR/${name}.c"

    # First check: does pika2c reject it?
    if ! "$TMPDIR/pika2c" < "$file" > "$cfile"; then
        pass; return
    fi

    # Second check: does C compiler reject it with strict flags?
    # Use -Werror to turn warnings into errors
    local STRICT_CFLAGS="-std=c11 -Werror -Wall -Wextra -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-gnu-auto-type -Wno-unused-function -Wno-unused-variable -Wno-gnu-statement-expression -Wno-parentheses-equality"
    if ! $CC $STRICT_CFLAGS "$cfile" lib/pika/rt.c -o "$TMPDIR/${name}.bin" 2>/dev/null; then
        pass; return
    fi

    # Both passed - this is a failure (invalid code was accepted)
    fail "should have failed"
}

run_runtime_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (runtime fail)..."

    local cfile="$TMPDIR/${name}.c"
    local binfile="$TMPDIR/${name}.bin"

    if ! "$TMPDIR/pika2c" < "$file" > "$cfile" 2>/dev/null; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS "$cfile" lib/pika/rt_cstd.c -o "$binfile"; then
        fail "compile error"
        return
    fi

    if "$binfile" 2>/dev/null; then
        fail "should have aborted"
    else
        pass
    fi
}

echo "=== pika2c  Success Tests ===" && echo
for f in test/pika/*.pka; do
    [ -f "$f" ] && run_test "$(basename ${f%.pka})" "$f"
done

echo && echo "=== pika2c  Compile-Time Fail Tests ===" && echo
for f in test/pika/fail/*.pka; do
    if [ -f "$f" ]; then
        case "$(basename "$f")" in runtime_*) continue;; esac
        run_fail_test "$(basename ${f%.pka})" "$f"
    fi
done

echo && echo "=== pika2c  Runtime Fail Tests ===" && echo
for f in test/pika/fail/runtime_*.pka; do
    [ -f "$f" ] && run_runtime_test "$(basename ${f%.pka})" "$f"
done

echo && echo "=== pika2c  Self-Hosting Tests ===" && echo

# Gen0: pika2c built by hare2c.py (Python) - already built above
# Gen1: pika2c built by Gen0
# Gen2: pika2c built by Gen1

PIKA_FILES="cmd/pika2c/*.pka"

printf "Testing %-40s " "gen1 (meta transpiles itself)..."
if cat $PIKA_FILES | "$TMPDIR/pika2c" > "$TMPDIR/gen1.c"; then
    if $CC $CFLAGS "$TMPDIR/gen1.c" lib/pika/rt_cstd.c -o "$TMPDIR/gen1"; then
        pass
    else
        fail "compile error"
    fi
else
    fail "transpile error"
fi

printf "Testing %-40s " "gen2 (gen1 transpiles itself)..."
if [ -f "$TMPDIR/gen1" ]; then
    if cat $PIKA_FILES | "$TMPDIR/gen1" > "$TMPDIR/gen2.c"; then
        if $CC $CFLAGS "$TMPDIR/gen2.c" lib/pika/rt_cstd.c -o "$TMPDIR/gen2"; then
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
    if cat $PIKA_FILES | "$TMPDIR/gen2" > "$TMPDIR/gen3.c"; then
        if $CC $CFLAGS "$TMPDIR/gen3.c" lib/pika/rt_cstd.c -o "$TMPDIR/gen3"; then
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

echo && echo "=== pika2c  Fixed-Point Test ===" && echo

printf "Testing %-40s " "fixed-point (gen2 == gen3 output)..."
if [ -f "$TMPDIR/gen2.c" ] && [ -f "$TMPDIR/gen3.c" ]; then
    if diff -q "$TMPDIR/gen2.c" "$TMPDIR/gen3.c" > /dev/null 2>&1; then
        pass
    else
        # Show first few differences for debugging
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
    # Test that both binaries produce identical output on same input
    if cat $PIKA_FILES | "$TMPDIR/gen2" > "$TMPDIR/test_gen2.c" && \
       cat $PIKA_FILES | "$TMPDIR/gen3" > "$TMPDIR/test_gen3.c"; then
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

echo && echo "=== pika2c  Summary ==="
TOTAL=$((PASS + FAIL))
printf "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Total: $TOTAL\n"


if [ $FAIL -eq 0 ]; then
    printf "${GREEN}All tests passed!${NC}\n"
    exit 0
fi
printf "${RED}Some tests failed.${NC}\n"
exit 1
