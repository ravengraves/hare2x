#!/bin/sh
# Build hare2c transpiler as WebAssembly module
set -e
cd "$(dirname "$0")/.."

OUT_DIR="build/wasm"
mkdir -p "$OUT_DIR/bin"
EM_CACHE="${EM_CACHE:-$(pwd)/$OUT_DIR/.emscripten_cache}"
mkdir -p "$EM_CACHE"
export EM_CACHE

HARE_FILES="cmd/hare2c/main.ha cmd/hare2c/arena.ha cmd/hare2c/strbuf.ha cmd/hare2c/dict.ha cmd/hare2c/token.ha cmd/hare2c/reader.ha cmd/hare2c/ast.ha cmd/hare2c/parser.ha cmd/hare2c/pattern.ha cmd/hare2c/transform.ha cmd/hare2c/rules.ha"

echo "=== Step 1a: Bootstrap - transpiling metacompiler with Python ==="
python3 cmd/hare2c.py $HARE_FILES -o "$OUT_DIR/hare2c_bootstrap.c"

echo "=== Step 1b: Compiling bootstrap transpiler ==="
CC=${CC:-clang}
# -flto breaks wasm sometimes. Maybe due to LONGJMP.
CFLAGS="-std=c11 -Os -Wall -Wextra -Wconversion -Wfloat-conversion \
    -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality \
    -Wno-implicit-int-conversion -Wno-unused-function \
    -ffast-math -ffunction-sections -fdata-sections -fno-builtin"

if ! command -v "$CC" > /dev/null 2>&1; then
    echo "clang not found. Install clang or set CC to your compiler."
    exit 1
fi

$CC $CFLAGS "$OUT_DIR/hare2c_bootstrap.c" lib/hare/rt.c -o "$OUT_DIR/hare2c_bootstrap"

echo "=== Step 1c: Self-hosting - transpiling metacompiler with itself ==="
cat $HARE_FILES | "$OUT_DIR/hare2c_bootstrap" > "$OUT_DIR/hare2c_meta.c"

rm -f "$OUT_DIR/hare2c_bootstrap.c" "$OUT_DIR/hare2c_bootstrap"

echo "=== Step 2: Compiling to WebAssembly ==="
WASM_CC=${WASM_CC:-emcc}
if ! command -v "$WASM_CC" > /dev/null 2>&1; then
    echo "emcc not found. Install and source emsdk_env.sh first:"
    echo "  https://emscripten.org/docs/getting_started/downloads.html#sdk-installation-instructions"
    echo "  source ~/emsdk/emsdk_env.sh"
    exit 1
fi

WASM_CFLAGS="$CFLAGS -Oz -ffreestanding -nostdlib"
WASM_LDFLAGS="-Wl,--gc-sections,--build-id=none,--strip-all -static -Wl,-s"
WASM_EXPORTS="['_main','_get_stdin_ptr','_set_stdin_len','_get_stdout_ptr','_get_stdout_len','_get_stderr_ptr','_get_stderr_len','_get_error_flag']"
$WASM_CC $WASM_CFLAGS \
    "$OUT_DIR/hare2c_meta.c" lib/hare/rt_wasm.c \
    -o "$OUT_DIR/bin/hare2c.wasm" \
    $WASM_LDFLAGS \
    -s STANDALONE_WASM=1 \
    -s IMPORTED_MEMORY=1 \
    -s INITIAL_MEMORY=33554432 \
    -s EXPORTED_FUNCTIONS="$WASM_EXPORTS" \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
    --no-entry

echo "=== Step 3: Creating hare2c.html ==="
python3 - wasm/index.html "$OUT_DIR/hare2c.html" << 'PYSCRIPT'
import json
import sys

def replace_placeholder(html, placeholder, path):
    with open(path) as f:
        data = f.read()
    token = f'"{placeholder}"'
    if token not in html:
        raise SystemExit(f"Placeholder {placeholder} not found in template")
    return html.replace(token, json.dumps(data))

with open(sys.argv[1]) as f:
    html = f.read()

html = replace_placeholder(html, "<RT_C>", "lib/hare/rt.c")
html = replace_placeholder(html, "<RT_CSTD>", "lib/hare/rt_cstd.c")
html = replace_placeholder(html, "<RT_WASM>", "lib/hare/rt_wasm.c")
html = replace_placeholder(html, "<WASM_LOADER>", "lib/wasm/load.js")

with open(sys.argv[2], "w") as f:
    f.write(html)
PYSCRIPT

echo ""
echo "=== Build complete ==="
echo "Output files:"
ls -la "$OUT_DIR/bin/hare2c.wasm" "$OUT_DIR/hare2c.html"
echo ""
echo "To test locally:"
echo "  cd $OUT_DIR && python3 -m http.server 8080"
echo "  Open http://localhost:8080/hare2c.html"
