#!/bin/sh
# Test script for hare2c.py (Python-based Hare to C11 transpiler)

set -e
cd "$(dirname "$0")"

RED='\033[0;31m' GREEN='\033[0;32m' NC='\033[0m'
PASS=0 FAIL=0
CC=${CC:-clang}
CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-gnu-auto-type -Wno-parentheses-equality -Wno-unused-function -Wno-unused-variable -Wno-gnu-statement-expression -Wno-unused-value -Wno-unused-parameter -ffast-math -O0 -march=native -mtune=native"

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }

echo "=== hare2c.py Building Runtime ==="
echo

printf "Compiling %-40s " "rt.o..."
if $CC -c $CFLAGS -fno-builtin ../lib/hare/rt.c -o rt.o; then
    pass
else
    fail "compile error"
    exit 1
fi

# Create temp directory for test outputs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR rt.o" EXIT

run_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name..."

    local cfile="$TMPDIR/${name}.c"
    local ofile="$TMPDIR/${name}.o"
    local binfile="$TMPDIR/${name}"

    if ! python3 ../cmd/hare2c.py "$file" -o "$cfile" >/dev/null 2>&1; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        fail "compile error"
        return
    fi

    if ! $CC rt.o "$ofile" -o "$binfile"; then
        fail "link error"
        return
    fi

    if "$binfile" >/dev/null 2>&1; then
        pass
    else
        fail "runtime error"
    fi
}

run_multifile_test() {
    local name="$1"
    shift
    local files="$@"
    printf "Testing %-40s " "$name..."

    local cfile="$TMPDIR/${name}.c"
    local ofile="$TMPDIR/${name}.o"
    local binfile="$TMPDIR/${name}"

    if ! python3 ../cmd/hare2c.py -N mypackage $files -o "$cfile" >/dev/null 2>&1; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        fail "compile error"
        return
    fi

    if ! $CC rt.o "$ofile" -o "$binfile"; then
        fail "link error"
        return
    fi

    if "$binfile" >/dev/null 2>&1; then
        pass
    else
        fail "runtime error"
    fi
}

run_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (should fail)..."

    local cfile="$TMPDIR/${name}.c"
    local ofile="$TMPDIR/${name}.o"

    if ! python3 ../cmd/hare2c.py "$file" -o "$cfile" &>/dev/null; then
        pass
        return
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        pass
        return
    fi

    fail "should have failed"
}

run_runtime_fail_test() {
    local name="$1"
    local file="$2"
    printf "Testing %-40s " "$name (runtime fail)..."

    local cfile="$TMPDIR/${name}.c"
    local ofile="$TMPDIR/${name}.o"
    local binfile="$TMPDIR/${name}"

    if ! python3 ../cmd/hare2c.py "$file" -o "$cfile" >/dev/null 2>&1; then
        fail "transpile error"
        return
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        fail "compile error"
        return
    fi

    if ! $CC rt.o "$ofile" -o "$binfile"; then
        fail "link error"
        return
    fi

    if "$binfile" >/dev/null 2>&1; then
        fail "should have aborted"
    else
        pass
    fi
}

echo && echo "=== hare2c.py Single-File Tests ===" && echo

for f in hare/*.ha; do
    name=$(basename "${f%.ha}")
    # Skip package files (they need multi-file compilation)
    case "$name" in pkg_*) continue;; esac
    [ -f "$f" ] && run_test "$name" "$f"
done

echo && echo "=== hare2c.py Multi-File Tests ===" && echo

run_multifile_test "pkg_combined" hare/pkg_main.ha hare/pkg_util.ha

echo && echo "=== hare2c.py Hare Fail Tests ===" && echo

for f in hare/fail/harebad_*.ha; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.ha}")
    # Remove "harebad_" prefix for display
    display_name="${basename_name#harebad_}"

    run_fail_test "hare/$display_name" "$f"
done

echo && echo "=== hare2c.py Pika Success Tests ===" && echo

for f in pika/*.pka; do
    [ -f "$f" ] || continue
    name="pika_$(basename "${f%.pka}")"
    printf "Testing %-40s " "pika/$(basename "${f%.pka}")..."

    cfile="$TMPDIR/${name}.c"
    ofile="$TMPDIR/${name}.o"
    binfile="$TMPDIR/${name}"

    if ! python3 ../cmd/hare2c.py "$f" -o "$cfile" >/dev/null 2>&1; then
        fail "transpile error"
        continue
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        fail "compile error"
        continue
    fi

    if ! $CC rt.o "$ofile" -o "$binfile"; then
        fail "link error"
        continue
    fi

    if "$binfile" >/dev/null 2>&1; then
        pass
    else
        fail "runtime error"
    fi
done

echo && echo "=== hare2c.py Pika Compile-Time Fail Tests ===" && echo

for f in pika/fail/*.pka; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.pka}")
    # Skip pika-prefixed tests
    case "$basename_name" in *pika*) continue;; esac
    # Skip runtime_* tests
    case "$basename_name" in runtime_*) continue;; esac

    name="pika_fail_${basename_name}"
    printf "Testing %-40s " "pika/$basename_name (should fail)..."

    cfile="$TMPDIR/${name}.c"
    ofile="$TMPDIR/${name}.o"

    if ! python3 ../cmd/hare2c.py "$f" -o "$cfile" >/dev/null 2>&1; then
        pass
        continue
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        pass
        continue
    fi

    fail "should have failed"
done

echo && echo "=== hare2c.py Pika Runtime Fail Tests ===" && echo

for f in pika/fail/runtime_*.pka; do
    [ -f "$f" ] || continue
    basename_name=$(basename "${f%.pka}")
    name="pika_fail_${basename_name}"
    printf "Testing %-40s " "pika/$basename_name (runtime fail)..."

    cfile="$TMPDIR/${name}.c"
    ofile="$TMPDIR/${name}.o"
    binfile="$TMPDIR/${name}"

    if ! python3 ../cmd/hare2c.py "$f" -o "$cfile" >/dev/null 2>&1; then
        fail "transpile error"
        continue
    fi

    if ! $CC $CFLAGS -c "$cfile" -o "$ofile"; then
        fail "compile error"
        continue
    fi

    if ! $CC rt.o "$ofile" -o "$binfile"; then
        fail "link error"
        continue
    fi

    if "$binfile" >/dev/null 2>&1; then
        fail "should have aborted"
    else
        pass
    fi
done

echo && echo "=== hare2c.py Summary ==="
TOTAL=$((PASS + FAIL))
printf "Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}  Total: %d\n" $PASS $FAIL $TOTAL

if [ $FAIL -eq 0 ]; then
    printf "${GREEN}All tests passed!${NC}\n"
    exit 0
fi
printf "${RED}Some tests failed.${NC}\n"
exit 1
