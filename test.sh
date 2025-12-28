#!/bin/bash
# Hare-to-C11 Transpiler Test Script

set -e
cd "$(dirname "$0")"

echo "=== Hare-to-C11 Transpiler Test Suite ==="
echo ""

# Compile runtime first
echo "Compiling runtime..."
gcc -c -std=c11 -w runtime.c -o runtime.o
echo ""

PASS=0
FAIL=0

for ha in examples/*.ha; do
    name=$(basename "$ha" .ha)
    c="examples/${name}.c"

    echo -n "Testing $name... "

    # Transpile
    if ! python3 hare2c.py "$ha" "$c"; then
        echo "❌ FAIL (transpile error)"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Compile
    if gcc -c -std=c11 -w "$c" -o "examples/${name}.o" 2>/dev/null; then
        echo "✅ PASS"
        PASS=$((PASS + 1))
    else
        echo "❌ FAIL (compile error)"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo ""

# Show how to link
echo "To link an executable (e.g., basic):"
echo "  gcc -std=c11 examples/basic.o runtime.o -o basic"
echo ""

# Cleanup object files
rm -f examples/*.o runtime.o

exit $FAIL