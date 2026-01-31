#!/bin/sh
# Test WebAssembly compilation of Hare code via hare2c + clang/wasm
set -e
cd "$(dirname "$0")/.."

OUT_DIR="build/wasm/test"
mkdir -p "$OUT_DIR"
EM_CACHE="${EM_CACHE:-$(pwd)/$OUT_DIR/.emscripten_cache}"
mkdir -p "$EM_CACHE"
export EM_CACHE

echo "=== Creating exported version of source ==="
# Add 'export' keyword to functions we want to expose to wasm
sed -e 's/^fn seed_rng/export fn seed_rng/' \
    -e 's/^fn rand_f64/export fn rand_f64/' \
    -e 's/^fn estimate_pi/export fn estimate_pi/' \
    test/hare/numeric_pi_monte_carlo.ha > "$OUT_DIR/pi_monte_carlo.ha"

echo "=== Transpiling ==="
python3 cmd/hare2c.py "$OUT_DIR/pi_monte_carlo.ha" -o "$OUT_DIR/pi_monte_carlo.c"

echo "=== Compiling to WebAssembly ==="
WASM_CC=${WASM_CC:-emcc}
if ! command -v "$WASM_CC" > /dev/null 2>&1; then
    echo "emcc not found. Install and source emsdk_env.sh first:"
    echo "  https://emscripten.org/docs/getting_started/downloads.html#sdk-installation-instructions"
    echo "  source ~/emsdk/emsdk_env.sh"
    exit 1
fi
if ! command -v emcc > /dev/null 2>&1; then
    echo "emcc not found. Install and source emsdk_env.sh first:"
    echo "  https://emscripten.org/docs/getting_started/downloads.html#sdk-installation-instructions"
    echo "  source ~/emsdk/emsdk_env.sh"
    exit 1
fi

echo "=== Compiling to WebAssembly ==="
emcc -std=c11 -Oz \
    "$OUT_DIR/pi_monte_carlo.c" lib/hare/rt_cstd.c \
    -o "$OUT_DIR/pi_monte_carlo.js" \
    -s EXPORTED_FUNCTIONS='["_seed_rng","_estimate_pi","_rand_f64","_main"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","HEAPU8","wasmMemory"]' \
    -s MODULARIZE=1 \
    -s EXPORT_NAME='createPiModule' \
    -s INITIAL_MEMORY=256KB \
    -s STACK_SIZE=32KB \
    -s TOTAL_STACK=32KB \
    --closure 0

echo "=== Generating HTML test page ==="
cat > "$OUT_DIR/pi_monte_carlo.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Monte Carlo Pi - Hare to WebAssembly</title>
    <style>
        :root {
            --bg: #fff;
            --fg: #000;
            --bg-secondary: #f5f5f5;
            --border: #ccc;
            --border-focus: #000;
            --muted: #666;
            --accent: #06c;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #000;
                --fg: #fff;
                --bg-secondary: #222;
                --border: #444;
                --border-focus: #fff;
                --muted: #888;
                --accent: #0f0;
            }
        }
        * { box-sizing: border-box; }
        body {
            font-family: monospace;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: var(--bg);
            color: var(--fg);
        }
        h1, h2 { margin: 0 0 15px 0; }
        p { color: var(--muted); margin: 0 0 15px 0; }
        button {
            background: var(--bg-secondary);
            color: var(--fg);
            border: 1px solid var(--border);
            padding: 8px 16px;
            font-family: monospace;
            font-size: 1em;
            cursor: pointer;
            margin-right: 10px;
        }
        button:hover { border-color: var(--border-focus); }
        input {
            background: var(--bg-secondary);
            color: var(--fg);
            border: 1px solid var(--border);
            padding: 6px 10px;
            font-family: monospace;
            font-size: 1em;
            width: 120px;
        }
        input:focus { outline: none; border-color: var(--border-focus); }
        label { margin-right: 15px; }
        .controls { margin-bottom: 15px; }
        #output {
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            padding: 15px;
            white-space: pre-wrap;
            margin-top: 15px;
        }
        .result { font-size: 1.3em; color: var(--accent); }
    </style>
</head>
<body>
    <h1>Monte Carlo Pi Estimation</h1>
    <p>Hare code transpiled to C, compiled to WebAssembly with Emscripten.</p>

    <div class="controls">
        <label>Seed: <input type="number" id="seed" value="31415"></label>
        <label>Samples: <input type="number" id="samples" value="100000"></label>
    </div>

    <button id="runBtn" disabled>Estimate Pi</button>
    <button id="runMainBtn" disabled>Run All Tests</button>

    <h2>Result</h2>
    <div id="output">Loading WebAssembly...</div>

    <script src="pi_monte_carlo.js"></script>
    <script>
        const outputEl = document.getElementById('output');
        const runBtn = document.getElementById('runBtn');
        const runMainBtn = document.getElementById('runMainBtn');
        let Module = null;
        let seed_rng = null;
        let estimate_pi = null;
        let rand_f64 = null;
        let wasm_main = null;

        createPiModule().then((mod) => {
            Module = mod;
            seed_rng = Module.cwrap('seed_rng', null, ['bigint']);
            estimate_pi = Module.cwrap('estimate_pi', 'number', ['number']);
            rand_f64 = Module.cwrap('rand_f64', 'number', []);
            wasm_main = Module.cwrap('main', 'number', []);
            outputEl.textContent = 'WebAssembly module loaded. Ready!';
            runBtn.disabled = false;
            runMainBtn.disabled = false;
        }).catch((err) => {
            outputEl.textContent = 'Failed to load WASM: ' + err.message;
        });

        document.getElementById('runBtn').addEventListener('click', () => {
            if (!seed_rng || !estimate_pi) return;
            const seed = parseInt(document.getElementById('seed').value, 10);
            const samples = parseInt(document.getElementById('samples').value, 10);

            const start = performance.now();
            seed_rng(BigInt(seed));
            const pi = estimate_pi(samples);
            const elapsed = (performance.now() - start).toFixed(2);

            const error = Math.abs(pi - Math.PI);
            outputEl.innerHTML = `Seed: ${seed}
Samples: ${samples.toLocaleString()}
<span class="result">Estimated Pi: ${pi.toFixed(10)}</span>
Actual Pi:     ${Math.PI.toFixed(10)}
Error:         ${error.toFixed(10)}
Time:          ${elapsed} ms`;
        });

        document.getElementById('runMainBtn').addEventListener('click', () => {
            if (!wasm_main) return;
            outputEl.textContent = 'Running main() tests...\n';
            try {
                Module._main();
                outputEl.textContent += 'All tests passed!';
            } catch (err) {
                const msg = err && err.message ? err.message : String(err);
                outputEl.textContent += 'Error: ' + msg;
            }
        });
    </script>
</body>
</html>
EOF

echo ""
echo "=== Build complete ==="
echo "Output files:"
ls -la "$OUT_DIR/pi_monte_carlo.js" "$OUT_DIR/pi_monte_carlo.html"
echo ""
echo "To test locally:"
echo "  cd $OUT_DIR && python3 -m http.server 8080"
echo "  Open http://localhost:8080/pi_monte_carlo.html"
