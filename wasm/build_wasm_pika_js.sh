#!/bin/sh
# Build pika2c transpiler as WebAssembly module and copy the JS demo page.
set -e
cd "$(dirname "$0")/.."

OUT_DIR="build/wasm"
mkdir -p "$OUT_DIR/bin"

bash wasm/build_wasm_pika.sh
cp wasm/pika2js.html "$OUT_DIR/pika2js.html"

python3 - "$OUT_DIR/pika2js.html" << 'PYSCRIPT'
import json
import sys
from pathlib import Path

html_path = Path(sys.argv[1])
runtime_path = Path("lib/javascript/runtime.js")
loader_path = Path("lib/wasm/load.js")

html = html_path.read_text()
runtime = runtime_path.read_text()
loader = loader_path.read_text()

token = '"<RUNTIME_JS>"'
if token not in html:
    raise SystemExit("Placeholder <RUNTIME_JS> not found in pika2js.html")

if '"__PIKA_STDIN__"' not in runtime:
    raise SystemExit("Placeholder __PIKA_STDIN__ not found in lib/javascript/runtime.js")

runtime_literal = json.dumps(runtime)
wrapper_lines = [
    "(function(global) {",
    f"    const __pika_runtime_template = {runtime_literal};",
    "    function buildPikaRuntime(stdinText) {",
    "        const stdinJson = JSON.stringify(stdinText || \"\");",
    "        return __pika_runtime_template.split('\"__PIKA_STDIN__\"').join(stdinJson);",
    "    }",
    "    if (typeof global !== \"undefined\") {",
    "        global.buildPikaRuntime = buildPikaRuntime;",
    "    }",
    "})(typeof window !== \"undefined\" ? window : self);",
]
wrapper = "\n".join(wrapper_lines)
html = html.replace(token, json.dumps(wrapper))
token = '"<WASM_LOADER>"'
if token not in html:
    raise SystemExit("Placeholder <WASM_LOADER> not found in pika2js.html")

html = html.replace(token, json.dumps(loader))
html_path.write_text(html)
PYSCRIPT

echo "=== Step 5: Creating pika2glsl.html ==="
python3 - wasm/pika2glsl.html "$OUT_DIR/pika2glsl.html" << 'PYSCRIPT'
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

html = replace_placeholder(html, "<GL_PK>", "glsl/gl.pka")
html = replace_placeholder(html, "<GLSL_VERTEX_DEMO>", "test/glsl/003_demo_vertex.pka")
html = replace_placeholder(html, "<GLSL_FRAGMENT_DEMO>", "test/glsl/003_demo_fragment.pka")
html = replace_placeholder(html, "<WASM_LOADER>", "lib/wasm/load.js")

with open(sys.argv[2], "w") as f:
    f.write(html)
PYSCRIPT

echo ""
echo "=== Build complete ==="
echo "Output files:"
ls -la "$OUT_DIR/bin/pika2c.wasm" "$OUT_DIR/pika2js.html" "$OUT_DIR/pika2glsl.html"
echo ""
echo "To test locally:"
echo "  cd $OUT_DIR && python3 -m http.server 8080"
echo "  Open http://localhost:8080/pika2js.html"
echo "  Open http://localhost:8080/pika2glsl.html"
