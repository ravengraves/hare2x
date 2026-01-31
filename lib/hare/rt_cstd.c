/* Hare Runtime (rt::) for C11 - Standard Library Version
 * Supports: GCC and Clang on Linux, macOS, Windows (clang/MinGW), Emscripten
 */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Platform-specific I/O */
#ifdef _WIN32
  #include <io.h>
  #include <process.h>
  #define posix_read  _read
  #define posix_write _write
  #define posix_exit  _exit
#elif defined(__EMSCRIPTEN__)
  #include <emscripten.h>
  #define posix_read(fd, buf, n)  (-1)  /* Not supported in wasm */
  #define posix_write(fd, buf, n) (-1)
  #define posix_exit(s)           exit(s)
#else
  #include <unistd.h>
  #define posix_read  read
  #define posix_write write
  #define posix_exit  _exit
#endif

/* GCC/Clang attributes */
#define HARE_NORETURN __attribute__((noreturn))
#define HARE_WEAK     __attribute__((weak))
#define HARE_USED     __attribute__((used))

/* Linker-provided symbols for hare_init/hare_fini sections (ELF only) */
typedef void (*hare_init_fn)(void);
#if defined(__ELF__) && !defined(__EMSCRIPTEN__)
  extern hare_init_fn __start_hare_init[] HARE_WEAK;
  extern hare_init_fn __stop_hare_init[] HARE_WEAK;
  extern hare_init_fn __start_hare_fini[] HARE_WEAK;
  extern hare_init_fn __stop_hare_fini[] HARE_WEAK;
  #ifdef HARE_TEST
    extern hare_init_fn __start_hare_test[] HARE_WEAK;
    extern hare_init_fn __stop_hare_test[] HARE_WEAK;
  #endif
  #define HARE_HAS_INIT_SECTIONS 1
#else
  #define HARE_HAS_INIT_SECTIONS 0
#endif

/* String type matching Hare's str */
typedef struct {
    uint8_t* data;
    size_t len;
} hare_str;

/* Error tag base for tagged unions */
#define HARE_ERROR_TAG_BASE 0x80000000U

/* Slice type for dynamic operations */
typedef struct {
    void* data;
    size_t length;
    size_t capacity;
} rt_slice;

/* Fixed error messages as hare_str (data, len) */
#define HARE_STR_LIT(s) { (uint8_t*)(s), sizeof(s) - 1 }
static const hare_str rt_fixed_errors[] = {
    HARE_STR_LIT("slice or array access out of bounds"),                  /* 0 */
    HARE_STR_LIT("type assertion failed"),                                /* 1 */
    HARE_STR_LIT("out of memory"),                                        /* 2 */
    HARE_STR_LIT("static insert/append exceeds slice capacity"),          /* 3 */
    HARE_STR_LIT("execution reached unreachable code (compiler bug)"),    /* 4 */
    HARE_STR_LIT("slice allocation capacity smaller than initializer"),   /* 5 */
    HARE_STR_LIT("assertion failed"),                                     /* 6 */
    HARE_STR_LIT("error occurred"),                                       /* 7 */
};
static const hare_str rt_unknown_error = HARE_STR_LIT("unknown error");

/* ==========================================================================
 * Core memory functions
 * ========================================================================== */

void rt_memcpy(void* restrict dest, const void* restrict src, size_t n) {
    memcpy(dest, src, n);
}

void rt_memmove(void* dest, const void* src, size_t n) {
    memmove(dest, src, n);
}

void rt_memset(void* dest, int c, size_t n) {
    memset(dest, c, n);
}

int rt_strcmp(hare_str a, hare_str b) {
    if (a.len != b.len) return 0;
    return memcmp(a.data, b.data, a.len) == 0;
}

/* ==========================================================================
 * I/O functions
 * ========================================================================== */

int64_t rt_write(int fd, const void* buf, size_t count) {
    return (int64_t)posix_write(fd, buf, (unsigned int)count);
}

int64_t rt_read(int fd, void* buf, size_t count) {
    return (int64_t)posix_read(fd, buf, (unsigned int)count);
}

/* ==========================================================================
 * Process control
 * ========================================================================== */

HARE_NORETURN
void rt_exit(int status) {
    posix_exit(status);
    __builtin_unreachable();
}

/* ==========================================================================
 * Abort functions
 * ========================================================================== */

HARE_WEAK HARE_NORETURN
void rt_abort_handler(hare_str path, uint64_t line, uint64_t col, hare_str msg) {
    fprintf(stderr, "abort");
    if (path.data && path.len > 0) {
        fprintf(stderr, " at %.*s", (int)path.len, (char*)path.data);
        if (line > 0) {
            fprintf(stderr, ":%lu:%lu", (unsigned long)line, (unsigned long)col);
        }
    }
    if (msg.data && msg.len > 0) {
        fprintf(stderr, ": %.*s\n", (int)msg.len, (char*)msg.data);
    } else {
        fprintf(stderr, ": unknown error\n");
    }
    exit(134);  /* 128 + SIGABRT(6) */
    __builtin_unreachable();
}

HARE_NORETURN
void rt_abort(hare_str* path, uint64_t line, uint64_t col, hare_str msg) {
    hare_str p = path ? *path : (hare_str){0, 0};
    rt_abort_handler(p, line, col, msg);
    __builtin_unreachable();
}

HARE_NORETURN
void rt_abort_fixed(hare_str* path, uint64_t line, uint64_t col, uint64_t i) {
    hare_str msg = (i < sizeof(rt_fixed_errors)/sizeof(rt_fixed_errors[0]))
                 ? rt_fixed_errors[i] : rt_unknown_error;
    hare_str p = path ? *path : (hare_str){0, 0};
    rt_abort_handler(p, line, col, msg);
    __builtin_unreachable();
}

/* ==========================================================================
 * Heap functions
 * ========================================================================== */

void* rt_calloc(size_t nmemb, size_t size) {
    return calloc(nmemb, size);
}

void* rt_malloc(size_t n) {
    return rt_calloc(1, n);
}

void rt_free(void* p) {
    free(p);
}

void* rt_realloc(void* p, size_t n) {
    return realloc(p, n);
}

void rt_ensure(rt_slice* s, size_t membsz) {
    size_t needed = s->capacity * membsz;
    if (s->data == NULL) {
        s->data = malloc(needed);
    } else {
        void* newdata = realloc(s->data, needed);
        if (newdata) {
            s->data = newdata;
        }
    }
}

void rt_unensure(rt_slice* s, size_t membsz) {
    (void)s;
    (void)membsz;
}

/* ==========================================================================
 * Init/Fini handlers
 * ========================================================================== */

void rt_init(void) {
#if HARE_HAS_INIT_SECTIONS
    if (__start_hare_init && __stop_hare_init) {
        for (hare_init_fn* fn = __start_hare_init; fn < __stop_hare_init; fn++) {
            if (*fn) (*fn)();
        }
    }
#endif
}

void rt_fini(void) {
#if HARE_HAS_INIT_SECTIONS
    if (__start_hare_fini && __stop_hare_fini) {
        for (hare_init_fn* fn = __start_hare_fini; fn < __stop_hare_fini; fn++) {
            if (*fn) (*fn)();
        }
    }
#endif
}

#ifdef HARE_TEST
void rt_run_tests(void) {
#if HARE_HAS_INIT_SECTIONS
    if (__start_hare_test && __stop_hare_test) {
        for (hare_init_fn* fn = __start_hare_test; fn < __stop_hare_test; fn++) {
            if (*fn) (*fn)();
        }
    }
#endif
}
#endif

/* ==========================================================================
 * Entry point
 * ========================================================================== */

extern void _main(void);

#ifdef HARE_TEST
int rt_start_c(void) {
    rt_init();
    rt_run_tests();
    rt_fini();
    return 0;
}
#else
int rt_start_c(void) {
    rt_init();
    _main();
    rt_fini();
    return 0;
}
#endif

HARE_WEAK
int main(void) {
    return rt_start_c();
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

typedef struct __hare_strings_dup_result {
    uint32_t tag;
    union {
        hare_str _str;
    } value;
} __hare_strings_dup_result;

/* Convert str to []u8 - returns a view (no copy) */
hare_slice_uint8_t strings_toutf8(hare_str s) {
    return (hare_slice_uint8_t){ s.data, s.len, s.len };
}

/* Convert []u8 to str without UTF-8 validation - returns a view (no copy) */
hare_str strings_fromutf8_unsafe(hare_slice_uint8_t in) {
    return (hare_str){ in.data, in.len };
}

/* Duplicate a string - allocates new memory */
__hare_strings_dup_result strings_dup(hare_str s) {
    if (s.len == 0 || s.data == NULL) {
        return (__hare_strings_dup_result){ .tag = 0U, .value._str = (hare_str){ NULL, 0 } };
    }
    uint8_t* copy = (uint8_t*)malloc(s.len);
    if (copy == NULL) {
        return (__hare_strings_dup_result){ .tag = HARE_ERROR_TAG_BASE + 1U };
    }
    memcpy(copy, s.data, s.len);
    return (__hare_strings_dup_result){ .tag = 0U, .value._str = (hare_str){ copy, s.len } };
}
