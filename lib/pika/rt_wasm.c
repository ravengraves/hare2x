/* Pika Runtime for WebAssembly
 *
 * Provides the runtime support for Pika programs compiled to WASM:
 * - stdin/stdout/stderr via memory buffers (accessible from JavaScript)
 * - Error signaling via traps for host handling
 *
 * Usage from JavaScript:
 *   1. Copy input data to get_stdin_ptr(), call set_stdin_len()
 *   2. Call main() - resets state, runs program, returns 0 on success
 *   3. Read output from get_stdout_ptr()/get_stdout_len()
 *   4. On error, check get_error_flag() and get_stderr_ptr()/get_stderr_len()
 */

#include <stdint.h>
#include <stddef.h>
#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
#define WASM_EXPORT EMSCRIPTEN_KEEPALIVE
#else
#define WASM_EXPORT __attribute__((used))
#endif

/* Error tracking */

/* ==========================================================================
 * I/O Buffers
 * ========================================================================== */

#define STDIN_BUFFER_SIZE  (1 * 1024 * 1024)  /* 1MB - ~15k lines of code */
#define STDOUT_BUFFER_SIZE (2 * 1024 * 1024)  /* 2MB */
#define STDERR_BUFFER_SIZE (64 * 1024)        /* 64KB */

static uint8_t stdin_buffer[STDIN_BUFFER_SIZE];
static size_t stdin_len = 0;
static size_t stdin_pos = 0;

static uint8_t stdout_buffer[STDOUT_BUFFER_SIZE];
static size_t stdout_len = 0;

static uint8_t stderr_buffer[STDERR_BUFFER_SIZE];
static size_t stderr_len = 0;

static int error_occurred = 0;

/* stdin - JS writes here before calling main() */
WASM_EXPORT uint8_t* get_stdin_ptr(void) { return stdin_buffer; }
WASM_EXPORT void set_stdin_len(size_t len) {
    stdin_len = len < STDIN_BUFFER_SIZE ? len : STDIN_BUFFER_SIZE;
    stdin_pos = 0;
}

/* stdout - JS reads after main() returns */
WASM_EXPORT uint8_t* get_stdout_ptr(void) { return stdout_buffer; }
WASM_EXPORT size_t get_stdout_len(void) { return stdout_len; }

/* stderr - JS reads on error */
WASM_EXPORT uint8_t* get_stderr_ptr(void) { return stderr_buffer; }
WASM_EXPORT size_t get_stderr_len(void) { return stderr_len; }

/* Error flag - set by abort/exit */
WASM_EXPORT int get_error_flag(void) { return error_occurred; }

/* ==========================================================================
 * Pika Types
 * ========================================================================== */

typedef struct { uint8_t* data; size_t len; } hare_str;

/* Error tag base for tagged unions */
#define HARE_ERROR_TAG_BASE 0x80000000U

/* Fixed error messages as hare_str (data, len) */
#define HARE_STR_LIT(s) { (uint8_t*)(s), sizeof(s) - 1 }
static const hare_str rt_fixed_errors[] = {
    HARE_STR_LIT("slice or array access out of bounds"),
    HARE_STR_LIT("type assertion failed"),
    HARE_STR_LIT("out of memory"),
    HARE_STR_LIT("static insert/append exceeds slice capacity"),
    HARE_STR_LIT("execution reached unreachable code"),
    HARE_STR_LIT("slice allocation capacity smaller than initializer"),
    HARE_STR_LIT("assertion failed"),
    HARE_STR_LIT("error occurred"),
};
static const hare_str rt_unknown_error = HARE_STR_LIT("unknown error");

/* ==========================================================================
 * Memory Functions - optimized with word-aligned operations
 * ========================================================================== */

/* Word size and alignment macros */
#define WASM_WORD_SIZE 4  /* WASM is 32-bit */
#define WASM_IS_ALIGNED(p) (((uintptr_t)(p) & (WASM_WORD_SIZE - 1)) == 0)

void rt_memcpy(void* restrict dest, const void* restrict src, size_t n) {
    uint8_t* d = (uint8_t*)dest;
    const uint8_t* s = (const uint8_t*)src;

    /* Word-aligned fast path */
    if (WASM_IS_ALIGNED(d) && WASM_IS_ALIGNED(s)) {
        uint32_t* dw = (uint32_t*)d;
        const uint32_t* sw = (const uint32_t*)s;

        /* 8-word unrolled (32 bytes) */
        while (n >= 8 * WASM_WORD_SIZE) {
            dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
            dw[4] = sw[4]; dw[5] = sw[5]; dw[6] = sw[6]; dw[7] = sw[7];
            dw += 8; sw += 8;
            n -= 8 * WASM_WORD_SIZE;
        }
        /* 4-word unrolled (16 bytes) */
        while (n >= 4 * WASM_WORD_SIZE) {
            dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
            dw += 4; sw += 4;
            n -= 4 * WASM_WORD_SIZE;
        }
        /* Single word */
        while (n >= WASM_WORD_SIZE) {
            *dw++ = *sw++;
            n -= WASM_WORD_SIZE;
        }
        d = (uint8_t*)dw;
        s = (const uint8_t*)sw;
    }
    /* Byte remainder */
    while (n--) *d++ = *s++;
}

void rt_memmove(void* dest, const void* src, size_t n) {
    uint8_t* d = (uint8_t*)dest;
    const uint8_t* s = (const uint8_t*)src;

    if (d < s || d >= s + n) {
        /* No overlap: forward copy */
        if (WASM_IS_ALIGNED(d) && WASM_IS_ALIGNED(s)) {
            uint32_t* dw = (uint32_t*)d;
            const uint32_t* sw = (const uint32_t*)s;
            while (n >= 4 * WASM_WORD_SIZE) {
                dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
                dw += 4; sw += 4;
                n -= 4 * WASM_WORD_SIZE;
            }
            while (n >= WASM_WORD_SIZE) {
                *dw++ = *sw++;
                n -= WASM_WORD_SIZE;
            }
            d = (uint8_t*)dw;
            s = (const uint8_t*)sw;
        }
        while (n--) *d++ = *s++;
    } else {
        /* Overlap: backward copy */
        d += n; s += n;
        if (WASM_IS_ALIGNED(d) && WASM_IS_ALIGNED(s)) {
            uint32_t* dw = (uint32_t*)d;
            const uint32_t* sw = (const uint32_t*)s;
            while (n >= 4 * WASM_WORD_SIZE) {
                dw -= 4; sw -= 4;
                dw[3] = sw[3]; dw[2] = sw[2]; dw[1] = sw[1]; dw[0] = sw[0];
                n -= 4 * WASM_WORD_SIZE;
            }
            while (n >= WASM_WORD_SIZE) {
                *--dw = *--sw;
                n -= WASM_WORD_SIZE;
            }
            d = (uint8_t*)dw;
            s = (const uint8_t*)sw;
        }
        while (n--) *--d = *--s;
    }
}

void rt_memset(void* dest, int c, size_t n) {
    uint8_t* p = (uint8_t*)dest;
    uint8_t byte = (uint8_t)c;

    /* Word-aligned fast path with pattern expansion */
    if (WASM_IS_ALIGNED(p)) {
        uint32_t* pw = (uint32_t*)p;
        uint32_t word = byte | ((uint32_t)byte << 8) |
                        ((uint32_t)byte << 16) | ((uint32_t)byte << 24);

        /* 8-word unrolled (32 bytes) */
        while (n >= 8 * WASM_WORD_SIZE) {
            pw[0] = word; pw[1] = word; pw[2] = word; pw[3] = word;
            pw[4] = word; pw[5] = word; pw[6] = word; pw[7] = word;
            pw += 8;
            n -= 8 * WASM_WORD_SIZE;
        }
        /* 4-word unrolled (16 bytes) */
        while (n >= 4 * WASM_WORD_SIZE) {
            pw[0] = word; pw[1] = word; pw[2] = word; pw[3] = word;
            pw += 4;
            n -= 4 * WASM_WORD_SIZE;
        }
        /* Single word */
        while (n >= WASM_WORD_SIZE) {
            *pw++ = word;
            n -= WASM_WORD_SIZE;
        }
        p = (uint8_t*)pw;
    }
    /* Byte remainder */
    while (n--) *p++ = byte;
}

/* Provide minimal libc shims for compiler-builtins */
void* memset(void* s, int c, size_t n) { rt_memset(s, c, n); return s; }
void* memcpy(void* dest, const void* src, size_t n) { rt_memcpy(dest, src, n); return dest; }
void* memmove(void* dest, const void* src, size_t n) { rt_memmove(dest, src, n); return dest; }

int rt_strcmp(hare_str a, hare_str b) {
    if (a.len != b.len) return 0;

    const uint8_t* pa = a.data;
    const uint8_t* pb = b.data;
    size_t n = a.len;

    /* Word-aligned fast path */
    if (WASM_IS_ALIGNED(pa) && WASM_IS_ALIGNED(pb)) {
        const uint32_t* wa = (const uint32_t*)pa;
        const uint32_t* wb = (const uint32_t*)pb;

        /* 8-word unrolled comparison (32 bytes) */
        while (n >= 8 * WASM_WORD_SIZE) {
            if (wa[0] != wb[0] || wa[1] != wb[1] ||
                wa[2] != wb[2] || wa[3] != wb[3] ||
                wa[4] != wb[4] || wa[5] != wb[5] ||
                wa[6] != wb[6] || wa[7] != wb[7]) return 0;
            wa += 8; wb += 8;
            n -= 8 * WASM_WORD_SIZE;
        }
        /* 4-word unrolled (16 bytes) */
        while (n >= 4 * WASM_WORD_SIZE) {
            if (wa[0] != wb[0] || wa[1] != wb[1] ||
                wa[2] != wb[2] || wa[3] != wb[3]) return 0;
            wa += 4; wb += 4;
            n -= 4 * WASM_WORD_SIZE;
        }
        /* Single word */
        while (n >= WASM_WORD_SIZE) {
            if (*wa++ != *wb++) return 0;
            n -= WASM_WORD_SIZE;
        }
        pa = (const uint8_t*)wa;
        pb = (const uint8_t*)wb;
    }
    /* Byte comparison for remainder */
    while (n--) {
        if (*pa++ != *pb++) return 0;
    }
    return 1;
}

/* Reset state - called by main() */
static void reset_all(void) {
    stdout_len = 0;
    stderr_len = 0;
    error_occurred = 0;
}

/* ==========================================================================
 * I/O Functions
 * ========================================================================== */

int64_t rt_write(int fd, const void* buf, size_t count) {
    uint8_t* target;
    size_t* len_ptr;
    size_t max_size;

    if (fd == 1) {
        target = stdout_buffer; len_ptr = &stdout_len; max_size = STDOUT_BUFFER_SIZE;
    } else if (fd == 2) {
        target = stderr_buffer; len_ptr = &stderr_len; max_size = STDERR_BUFFER_SIZE;
    } else {
        return (int64_t)count;
    }

    size_t available = max_size - *len_ptr;
    size_t to_write = count < available ? count : available;
    if (to_write > 0) {
        rt_memcpy(target + *len_ptr, buf, to_write);
        *len_ptr += to_write;
    }
    return (int64_t)to_write;
}

int64_t rt_read(int fd, void* buf, size_t count) {
    if (fd != 0) return -1;
    size_t available = stdin_len - stdin_pos;
    if (available == 0) return 0;
    size_t to_read = count < available ? count : available;
    rt_memcpy(buf, stdin_buffer + stdin_pos, to_read);
    stdin_pos += to_read;
    return (int64_t)to_read;
}

/* ==========================================================================
 * Process Control
 * ========================================================================== */

__attribute__((noreturn))
void rt_exit(int status) {
    error_occurred = (status != 0);
    __builtin_trap();
}

/* ==========================================================================
 * Abort Handling
 * ========================================================================== */

static void stderr_write(hare_str s) {
    if (!s.data || !s.len) return;
    size_t available = STDERR_BUFFER_SIZE - stderr_len;
    size_t to_write = s.len < available ? s.len : available;
    if (to_write > 0) {
        rt_memcpy(stderr_buffer + stderr_len, s.data, to_write);
        stderr_len += to_write;
    }
}

static void stderr_write_int(uint64_t n) {
    char buf[24];
    int i = 23;
    buf[i] = '\0';
    if (n == 0) { stderr_write((hare_str){(uint8_t*)"0", 1}); return; }
    while (n > 0 && i > 0) { buf[--i] = (char)('0' + (n % 10)); n /= 10; }
    stderr_write((hare_str){(uint8_t*)&buf[i], (size_t)(23 - i)});
}

__attribute__((noreturn))
void rt_abort_handler(hare_str path, uint64_t line, uint64_t col, hare_str msg) {
    error_occurred = 1;
    stderr_write((hare_str){(uint8_t*)"abort", 5});
    if (path.data && path.len > 0) {
        stderr_write((hare_str){(uint8_t*)" at ", 4});
        stderr_write(path);
        if (line > 0) {
            stderr_write((hare_str){(uint8_t*)":", 1});
            stderr_write_int(line);
            stderr_write((hare_str){(uint8_t*)":", 1});
            stderr_write_int(col);
        }
    }
    stderr_write((hare_str){(uint8_t*)": ", 2});
    stderr_write(msg.data && msg.len ? msg : rt_unknown_error);
    stderr_write((hare_str){(uint8_t*)"\n", 1});
    __builtin_trap();
}

__attribute__((noreturn))
void rt_abort(hare_str* path, uint64_t line, uint64_t col, hare_str msg) {
    hare_str p = path ? *path : (hare_str){0, 0};
    rt_abort_handler(p, line, col, msg);
}

__attribute__((noreturn))
void rt_abort_fixed(hare_str* path, uint64_t line, uint64_t col, uint64_t i) {
    hare_str msg = (i < sizeof(rt_fixed_errors)/sizeof(rt_fixed_errors[0]))
                 ? rt_fixed_errors[i] : rt_unknown_error;
    hare_str p = path ? *path : (hare_str){0, 0};
    rt_abort_handler(p, line, col, msg);
}

/* Stub initializer for standalone wasm builds */
__attribute__((used))
void _initialize(void) { }

/* ==========================================================================
 * Entry Point
 * ========================================================================== */

extern void _main(void);

WASM_EXPORT
int main(void) {
    reset_all();
    _main();
    return error_occurred ? 1 : 0;
}

/* ==========================================================================
 * strings:: module - string/byte slice conversions
 * ========================================================================== */

/* Slice type for []u8 - matches transpiler-generated hare_slice_uint8_t */
typedef struct {
    uint8_t* data;
    size_t len;
    size_t cap;
} hare_slice_uint8_t;

/* Convert str to []u8 - returns a view (no copy) */
hare_slice_uint8_t strings_toutf8(hare_str s) {
    return (hare_slice_uint8_t){ s.data, s.len, s.len };
}

/* Convert []u8 to str without UTF-8 validation - returns a view (no copy) */
hare_str strings_fromutf8_unsafe(hare_slice_uint8_t in) {
    return (hare_str){ in.data, in.len };
}
