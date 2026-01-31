function createWasmLoader(options) {
    const opts = options || {};
    const defaultInitialPages = Number.isFinite(opts.initialPages) ? opts.initialPages : 512;
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    function makeEnv(initialPages) {
        return {
            memoryBase: 0,
            tableBase: 0,
            memory: new WebAssembly.Memory({ initial: initialPages, maximum: initialPages }),
            table: new WebAssembly.Table({ initial: 0, element: 'anyfunc' }),
        };
    }

    function loadWasm(path, loadOptions) {
        const initialPages = (loadOptions && Number.isFinite(loadOptions.initialPages))
            ? loadOptions.initialPages
            : defaultInitialPages;
        return fetch(path)
            .then((response) => {
                if (!response.ok) {
                    throw new Error("Failed to load " + path + " (" + response.status + ")");
                }
                return response.arrayBuffer();
            })
            .then((bytes) => {
                const env = makeEnv(initialPages);
                return WebAssembly.instantiate(bytes, { env }).then((result) => ({
                    instance: result.instance,
                    memory: env.memory,
                }));
            });
    }

    function createMemoryAccess(memory) {
        let heapU8 = null;

        function refreshHeap() {
            if (!heapU8 || heapU8.buffer !== memory.buffer) {
                heapU8 = new Uint8Array(memory.buffer);
            }
        }

        function readUtf8(ptr, len) {
            if (len === 0) return "";
            refreshHeap();
            return decoder.decode(heapU8.subarray(ptr, ptr + len));
        }

        function writeBytes(ptr, bytes) {
            refreshHeap();
            heapU8.fill(0, ptr, ptr + bytes.length + 1);
            heapU8.set(bytes, ptr);
        }

        function getHeapU8() {
            refreshHeap();
            return heapU8;
        }

        return {
            refreshHeap,
            readUtf8,
            writeBytes,
            getHeapU8,
        };
    }

    function bindExports(exports, required) {
        const out = {};
        for (let i = 0; i < required.length; i += 1) {
            const name = required[i];
            if (typeof exports[name] !== "function") {
                throw new Error("Missing export: " + name);
            }
            out[name] = exports[name];
        }
        return out;
    }

    return {
        encoder,
        decoder,
        loadWasm,
        createMemoryAccess,
        bindExports,
    };
}
