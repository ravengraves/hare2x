#!/bin/sh
# Build pika2c transpiler as WebAssembly module
set -e
cd "$(dirname "$0")/.."

OUT_DIR="build/wasm"
mkdir -p "$OUT_DIR/bin"
EM_CACHE="${EM_CACHE:-$(pwd)/$OUT_DIR/.emscripten_cache}"
mkdir -p "$EM_CACHE"
export EM_CACHE

PIKA_FILES="cmd/pika2c/*.pka"

echo "=== Step 1a: Bootstrap - transpiling pika2c with Python ==="
python3 cmd/hare2c.py $PIKA_FILES -o "$OUT_DIR/pika2c_bootstrap.c"

echo "=== Step 1b: Compiling bootstrap transpiler ==="
CC=${CC:-clang}
CFLAGS="-std=c11 -Oz -Wall -Wextra -Wconversion -Wfloat-conversion \
    -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality \
    -Wno-implicit-int-conversion -Wno-unused-function \
    -ffast-math -ffunction-sections -fdata-sections -fno-builtin \
    -nostdlib -ffreestanding -fno-asynchronous-unwind-tables -fno-unwind-tables \
    -fno-stack-protector -fno-ident -fno-PIC -flto"

if ! command -v "$CC" > /dev/null 2>&1; then
    echo "clang not found. Install clang or set CC to your compiler."
    exit 1
fi

$CC $CFLAGS "$OUT_DIR/pika2c_bootstrap.c" lib/pika/rt.c -o "$OUT_DIR/pika2c_bootstrap"

echo "=== Step 1c: Self-hosting - transpiling pika2c with itself ==="
cat $PIKA_FILES | "$OUT_DIR/pika2c_bootstrap" > "$OUT_DIR/pika2c_meta.c"

rm -f "$OUT_DIR/pika2c_bootstrap.c" "$OUT_DIR/pika2c_bootstrap"

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
    "$OUT_DIR/pika2c_meta.c" lib/pika/rt_wasm.c \
    -o "$OUT_DIR/bin/pika2c.wasm" \
    $WASM_LDFLAGS \
    -s STANDALONE_WASM=1 \
    -s IMPORTED_MEMORY=1 \
    -s INITIAL_MEMORY=33554432 \
    -s EXPORTED_FUNCTIONS="$WASM_EXPORTS" \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
    --no-entry

echo "=== Step 3: Creating pika2c.html ==="
python3 - wasm/index.html "$OUT_DIR/pika2c.html" << 'PYSCRIPT'
import json
import re
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

html = html.replace('Hare2C Transpiler', 'Pika2C Transpiler')
html = html.replace('Hare Input', 'Pika Input')
html = html.replace('Enter Hare code', 'Enter Pika code')
html = html.replace('hare2c.wasm', 'pika2c.wasm')

pika_example = '''        const exampleCode = `// Pika example
use strings;
use rt;

export fn _main() void = {
    let msg = "       🐇
  Hello, Pika!
  ¡Hola, Pika!
  Γεια σου, Πίκα!
  Привіт, Піка!
  こんにちは、ピカ!
  안녕, 피카!
  你好，皮卡！
";
    print(msg);
};

fn print(msg: str) void = {
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
`;'''
html = re.sub(r'        const exampleCode = `.*?`;', pika_example, html, flags=re.DOTALL)

html = replace_placeholder(html, "<RT_C>", "lib/pika/rt.c")
html = replace_placeholder(html, "<RT_CSTD>", "lib/pika/rt_cstd.c")
html = replace_placeholder(html, "<RT_WASM>", "lib/pika/rt_wasm.c")
html = replace_placeholder(html, "<WASM_LOADER>", "lib/wasm/load.js")

with open(sys.argv[2], 'w') as f:
    f.write(html)
PYSCRIPT

echo ""
echo "=== Build complete ==="
echo "Output files:"
ls -la "$OUT_DIR/bin/pika2c.wasm" "$OUT_DIR/pika2c.html"
echo ""
echo "To test locally:"
echo "  cd $OUT_DIR && python3 -m http.server 8080"
echo "  Open http://localhost:8080/pika2c.html"
