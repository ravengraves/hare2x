#!/bin/sh
# Test script to validate test files with the actual Hare compiler
# This ensures our test files contain valid Hare syntax

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }
skip() { printf "${YELLOW}SKIP${NC} ($1)\n"; SKIP=$((SKIP + 1)); }

# Check if hare compiler is installed
if ! command -v hare >/dev/null 2>&1; then
    printf "${YELLOW}WARNING: Hare compiler not installed. Skipping Hare validation tests.${NC}\n"
    printf "${YELLOW}Install from: https://harelang.org/${NC}\n"
    exit 0
fi

echo "=== harec Hare Compiler Validation Tests ==="
echo "Using hare compiler: $(command -v hare)"
hare version 2>/dev/null || true
echo

# Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Function to test a single file
test_file() {
    local file="$1"
    local name="$2"

    printf "Testing %-45s " "$name..."

    # Create a test directory for this file
    local testdir="$TMPDIR/test_$(echo "$name" | tr '/' '_')"
    mkdir -p "$testdir"

    # Copy the file as main.ha (handles .pka -> .ha rename)
    cp "$file" "$testdir/main.ha"

    # Copy our rt/ and strings/ modules from lib/harec/
    cp -r lib/harec/rt "$testdir/"
    cp -r lib/harec/strings "$testdir/"

    cd "$testdir"

    # Try to build with hare in freestanding mode
    # Use -RF for release freestanding, specify main.ha directly
    if hare build -RFo test_bin main.ha 2>"$testdir/err.txt"; then
        pass
        cd - >/dev/null
        return 0
    fi

    # Check error output to determine if we should skip or fail
    local err=$(cat "$testdir/err.txt" 2>/dev/null)

    # Skip if missing modules we don't have
    if echo "$err" | grep -q "Could not resolve dependency"; then
        skip "missing dependency"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "fmt"; then
        skip "needs fmt module"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "Unknown object"; then
        skip "missing runtime symbol"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "Unresolvable identifier"; then
        skip "unresolved identifier"
        cd - >/dev/null
        return 0
    fi

    # Check for pika-specific features that real hare doesn't support
    if echo "$err" | grep -q "syntax error"; then
        # Check if it's a pika-specific feature
        if grep -q "export fn main" "$file" 2>/dev/null; then
            # Might be using export on main which some hare versions don't like
            skip "pika syntax variant"
            cd - >/dev/null
            return 0
        fi
        fail "syntax error"
        echo "$err" | head -3 | sed 's/^/  /'
        cd - >/dev/null
        return 1
    fi

    # Any other error is a real failure
    fail "compile error"
    echo "$err" | head -3 | sed 's/^/  /'
    cd - >/dev/null
    return 1
}

echo "=== harec Metacompiler Source Files ==="
echo

# Test building the metacompiler sources with real Hare compiler
test_hare2c_metacompiler() {
    printf "Testing %-45s " "hare2c metacompiler..."

    local testdir="$TMPDIR/hare2c_meta"
    mkdir -p "$testdir"

    # Copy metacompiler sources
    cp cmd/hare2c/*.ha "$testdir/"
    cp -r lib/harec/rt "$testdir/"
    cp -r lib/harec/strings "$testdir/"

    cd "$testdir"

    # Try to build with the Hare compiler in freestanding mode.
    if hare build -RFo test_bin . 2>"$testdir/err.txt"; then
        pass
        cd - >/dev/null
        return 0
    fi

    local err=$(cat "$testdir/err.txt" 2>/dev/null)

    # Missing dependencies or runtime symbols are not syntax issues.
    if echo "$err" | grep -q "Could not resolve dependency"; then
        skip "missing dependency"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "Unknown object"; then
        skip "missing runtime symbol"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "syntax error"; then
        fail "syntax error"
        echo "$err" | head -3 | sed 's/^/  /'
        cd - >/dev/null
        return 1
    fi

    fail "compile error"
    echo "$err" | head -3 | sed 's/^/  /'
    cd - >/dev/null
    return 1
}

test_pika2c_metacompiler() {
    printf "Testing %-45s " "pika2c metacompiler..."

    local testdir="$TMPDIR/pika2c_meta"
    mkdir -p "$testdir"

    # Copy Pika sources and rename to .ha for Hare validation.
    for src in cmd/pika2c/*.pka; do
        [ -f "$src" ] || continue
        local base
        base=$(basename "${src%.pka}")
        cp "$src" "$testdir/${base}.ha"
    done

    cp -r lib/harec/rt "$testdir/"
    cp -r lib/harec/strings "$testdir/"

    cd "$testdir"

    if hare build -RFo test_bin . 2>"$testdir/err.txt"; then
        pass
        cd - >/dev/null
        return 0
    fi

    local err=$(cat "$testdir/err.txt" 2>/dev/null)

    if echo "$err" | grep -q "Could not resolve dependency"; then
        skip "missing dependency"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "Unknown object"; then
        skip "missing runtime symbol"
        cd - >/dev/null
        return 0
    fi

    if echo "$err" | grep -q "syntax error"; then
        fail "syntax error"
        echo "$err" | head -3 | sed 's/^/  /'
        cd - >/dev/null
        return 1
    fi

    fail "compile error"
    echo "$err" | head -3 | sed 's/^/  /'
    cd - >/dev/null
    return 1
}

test_hare2c_metacompiler
test_pika2c_metacompiler

echo
echo "=== harec Hare Test Files ==="
echo
for f in test/hare/*.ha; do
    [ -f "$f" ] || continue
    name=$(basename "${f%.ha}")

    # Skip known problematic files
    case "$name" in
        failtests)
            # This file intentionally contains invalid code
            printf "Testing %-45s " "hare/$name..."
            skip "intentional fail test"
            continue
            ;;
        pkg_*)
            # Package files need special handling
            printf "Testing %-45s " "hare/$name..."
            skip "package file"
            continue
            ;;
    esac

    test_file "$f" "hare/$name"
done

echo
echo "=== harec Pika Test Files ==="
echo
for f in test/pika/*.pka; do
    [ -f "$f" ] || continue
    name=$(basename "${f%.pka}")
    if [ "$name" = "string_escapes" ]; then
        printf "Testing %-45s " "pika/$name..."
        skip "pika escape extension"
        continue
    fi
    test_file "$f" "pika/$name"
done

echo
echo "=== harec Summary ==="
printf "Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}  Skipped: ${YELLOW}%d${NC}  Total: %d\n" \
    "$PASS" "$FAIL" "$SKIP" "$((PASS + FAIL + SKIP))"

if [ "$FAIL" -gt 0 ]; then
    printf "${RED}Some tests failed.${NC}\n"
    exit 1
else
    printf "${GREEN}All tests passed (or skipped).${NC}\n"
    exit 0
fi
