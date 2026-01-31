#!/bin/bash
# SYCL Test Runner - CPU Backend (Native CPU)
# Runs all pika SYCL kernel tests using pure C11 harnesses

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL=0
PASSED=0
FAILED=0

echo "======================================================================"
echo "  Pika SYCL Test Runner - CPU Backend (Native CPU)"
echo "======================================================================"
echo ""

# Source Intel oneAPI
if [ -f "/opt/intel/oneapi/setvars.sh" ]; then
    source /opt/intel/oneapi/setvars.sh --force > /dev/null 2>&1 || true
elif [ -f "$HOME/intel/oneapi/setvars.sh" ]; then
    source "$HOME/intel/oneapi/setvars.sh" --force > /dev/null 2>&1 || true
fi

# Check compiler
SYCL_LD="$LD_LIBRARY_PATH"
SYCL_INSTALL_PREFIX="${SYCL_INSTALL_PREFIX:-}"
if [ -z "$SYCL_CXX" ]; then
    if [ -f "$HOME/sycl_workspace/llvm/build/install/bin/clang++" ]; then
        SYCL_CXX="$HOME/sycl_workspace/llvm/build/install/bin/clang++"
        SYCL_INSTALL_PREFIX="$HOME/sycl_workspace/llvm/build/install"
    elif command -v icpx &> /dev/null; then
        SYCL_CXX="icpx"
    elif command -v dpcpp &> /dev/null; then
        SYCL_CXX="dpcpp"
    fi
fi

if [ -z "$SYCL_CXX" ]; then
    echo -e "${RED}No SYCL compiler found (icpx/dpcpp/clang++). Skipping CPU SYCL tests.${NC}"
    exit 0
fi

CC="${CC:-gcc}"

if [ -n "$SYCL_INSTALL_PREFIX" ]; then
    if [ -n "$SYCL_LD" ]; then
        SYCL_LD="$SYCL_LD:$SYCL_INSTALL_PREFIX/lib"
    else
        SYCL_LD="$SYCL_INSTALL_PREFIX/lib"
    fi
fi

echo -e "${GREEN}Using:${NC} $SYCL_CXX"
echo ""

# Prefer OpenCL CPU if available, otherwise use Native CPU.
SYCL_LS=""
if [ -n "$SYCL_INSTALL_PREFIX" ] && [ -x "$SYCL_INSTALL_PREFIX/bin/sycl-ls" ]; then
    SYCL_LS="$SYCL_INSTALL_PREFIX/bin/sycl-ls"
elif command -v sycl-ls &> /dev/null; then
    SYCL_LS="sycl-ls"
fi

if [ -z "$SYCL_DEVICE_SELECTOR" ]; then
    if [ -n "$SYCL_LS" ] && LD_LIBRARY_PATH="$SYCL_LD" "$SYCL_LS" 2>/dev/null | grep -q "opencl:cpu"; then
        SYCL_DEVICE_SELECTOR="opencl:cpu"
    else
        SYCL_DEVICE_SELECTOR="native_cpu:cpu"
    fi
fi

# CPU tests require spir64_x86_64 images.
if [ -z "$SYCL_TARGETS" ] || [[ ",$SYCL_TARGETS," != *,spir64_x86_64,* ]]; then
    if [ -n "$SYCL_TARGETS" ] && [ "$SYCL_TARGETS" != "spir64_x86_64" ]; then
        echo "Note: overriding SYCL_TARGETS for CPU tests (was '$SYCL_TARGETS')."
    fi
    SYCL_TARGETS="spir64_x86_64"
fi

SYCL_FLAGS="-fsycl -std=c++17 -O2 -fsycl-targets=$SYCL_TARGETS"

RUN_ONEAPI_SELECTOR="${ONEAPI_DEVICE_SELECTOR:-$SYCL_DEVICE_SELECTOR}"
RUN_SYCL_FILTER="${SYCL_DEVICE_FILTER:-$SYCL_DEVICE_SELECTOR}"

echo -e "${BLUE}Device selector:${NC} $SYCL_DEVICE_SELECTOR"
echo -e "${BLUE}SYCL targets:${NC} $SYCL_TARGETS"
echo ""

cd "$(dirname "$0")/.."

# Compile SYCL runtime as shared library
TESTDIR=test/sycl/
RUNTIME_SO="$TESTDIR/libpika_sycl_runtime.so"
if ! $SYCL_CXX -w $SYCL_FLAGS -fPIC -shared \
    lib/sycl/pika_sycl_runtime.cpp -o "$RUNTIME_SO" 2>/dev/null; then
    echo -e "${RED}Runtime compilation failed${NC}"
    if [ "$SYCL_TARGETS" = "spir64_x86_64" ]; then
        echo "Hint: spir64_x86_64 requires an OpenCL CPU runtime for opencl-aot."
    fi
    exit 1
fi

# Test each kernel
for test_pka in test/sycl/*.pka; do
    [ -f "$test_pka" ] || continue

    test_name=$(basename "$test_pka" .pka)
    harness_c="$TESTDIR/${test_name}.c"
    TOTAL=$((TOTAL + 1))

    echo -n "  [$TOTAL] $test_name ... "

    if [ ! -f "$harness_c" ]; then
        echo -e "${RED}FAIL${NC} (no harness)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Transpile kernel
    kernel_hpp="$TESTDIR/${test_name}.hpp"
    if ! (echo "-T sycl"; cat "$test_pka") | ./build/pika2c > "$kernel_hpp" 2>&1; then
        echo -e "${RED}FAIL${NC} (transpile)"
        FAILED=$((FAILED + 1))
        continue
    fi

    kernel_src="$kernel_hpp"
    kernel_ext="$TESTDIR/${test_name}_ext.hpp"
    EXTRA_SYCL_CPPFLAGS=""
    if [ -f "$kernel_ext" ]; then
        EXTRA_SYCL_CPPFLAGS="-include $kernel_ext"
    fi

    # Build kernel as shared library (.hpp directly with -DPIKA_SYCL_IMPL)
    kernel_so="$TESTDIR/lib${test_name}.so"
    if ! $SYCL_CXX $SYCL_FLAGS -fPIC -shared \
        -DPIKA_SYCL_IMPL -x c++ -I"$TESTDIR" -I lib/sycl $EXTRA_SYCL_CPPFLAGS \
        "$kernel_src" -o "$kernel_so" 2>/dev/null; then
        echo -e "${RED}FAIL${NC} (compile)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Compile C11 harness
    harness_obj="$TESTDIR/${test_name}_harness.o"
    if ! $CC -std=c11 -O2 -I lib/sycl -c "$harness_c" -o "$harness_obj" 2>/dev/null; then
        echo -e "${RED}FAIL${NC} (harness)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Link
    SYCL_RPATH_FLAGS="-Wl,-rpath,$TESTDIR"
    if [ -n "$SYCL_INSTALL_PREFIX" ]; then
        SYCL_RPATH_FLAGS="$SYCL_RPATH_FLAGS -Wl,-rpath,$SYCL_INSTALL_PREFIX/lib"
        SYCL_LINK_FLAGS="-L$SYCL_INSTALL_PREFIX/lib -lsycl -lstdc++ -lm"
    else
        SYCL_LINK_FLAGS="-lsycl -lstdc++ -lm"
    fi
    test_exe="$TESTDIR/${test_name}_test"
    if ! $CC "$harness_obj" \
        -L"$TESTDIR" -l"${test_name}" -lpika_sycl_runtime \
        $SYCL_LINK_FLAGS $SYCL_RPATH_FLAGS -o "$test_exe" 2>/dev/null; then
        echo -e "${RED}FAIL${NC} (link)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Run
    # if ! bash -c "export LD_LIBRARY_PATH=$SYCL_LD; $test_exe 1>/dev/null"; then
    if CUDA_VISIBLE_DEVICES="" ONEAPI_DEVICE_SELECTOR="$RUN_ONEAPI_SELECTOR" SYCL_DEVICE_FILTER="$RUN_SYCL_FILTER" \
        LD_LIBRARY_PATH="$TESTDIR:$SYCL_LD" ./"$test_exe" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (run)"
        FAILED=$((FAILED + 1))
    fi
    rm $test_exe
done

echo ""
echo "======================================================================"
echo "  CPU Backend: $PASSED/$TOTAL passed"
echo "======================================================================"

[ $FAILED -eq 0 ] || exit 1
