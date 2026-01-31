/* Hare Runtime (rt::) for C11 */
#include <stdint.h>
#include <stddef.h>

/* Linker-provided symbols for hare_init/hare_fini sections */
typedef void (*hare_init_fn)(void);
extern hare_init_fn __start_hare_init[] __attribute__((weak));
extern hare_init_fn __stop_hare_init[] __attribute__((weak));
extern hare_init_fn __start_hare_fini[] __attribute__((weak));
extern hare_init_fn __stop_hare_fini[] __attribute__((weak));
#ifdef HARE_TEST
extern hare_init_fn __start_hare_test[] __attribute__((weak));
extern hare_init_fn __stop_hare_test[] __attribute__((weak));
#endif

/* String type matching Hare's str */
typedef struct { uint8_t* data; size_t len; } hare_str;

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
static const hare_str rt_abort_prefix = HARE_STR_LIT("abort: ");
static const hare_str rt_newline = HARE_STR_LIT("\n");

/* ==========================================================================
 * Core memory functions - optimized with unrolling for SIMD vectorization
 *
 * NOTE: Compile with -fno-builtin to prevent the compiler from replacing
 * loops with implicit memcpy/memset calls.
 *
 * Strategy:
 *   1. 64-byte unrolled loops (8 words) - enables SIMD vectorization
 *   2. Single word loop for remainder
 *   3. Byte loop for final bytes or unaligned cases
 * ========================================================================== */

/* Word size detection and alignment macros */
#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFULL
	#define HARE_WORD_SIZE 8
	#define HARE_IS_64BIT 1
#else
	#define HARE_WORD_SIZE 4
	#define HARE_IS_64BIT 0
#endif
#define HARE_IS_ALIGNED(p) (((uintptr_t)(p) & (HARE_WORD_SIZE - 1)) == 0)

void rt_memcpy(void* __restrict__ dest, const void* __restrict__ src, size_t n) {
	uint8_t* __restrict__ d = (uint8_t*)dest;
	const uint8_t* __restrict__ s = (const uint8_t*)src;

	/* Fast path: word-aligned, use unrolled copies */
	if (HARE_IS_ALIGNED(d) && HARE_IS_ALIGNED(s)) {
		size_t* dw = (size_t*)d;
		const size_t* sw = (const size_t*)s;

		/* 64-byte unrolled loop (8 words at a time) - SIMD-friendly */
		while (n >= 8 * HARE_WORD_SIZE) {
			dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
			dw[4] = sw[4]; dw[5] = sw[5]; dw[6] = sw[6]; dw[7] = sw[7];
			dw += 8; sw += 8;
			n -= 8 * HARE_WORD_SIZE;
		}
		/* 32-byte unrolled (4 words) */
		while (n >= 4 * HARE_WORD_SIZE) {
			dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
			dw += 4; sw += 4;
			n -= 4 * HARE_WORD_SIZE;
		}
		/* Single word loop */
		while (n >= HARE_WORD_SIZE) {
			*dw++ = *sw++;
			n -= HARE_WORD_SIZE;
		}
		d = (uint8_t*)dw;
		s = (const uint8_t*)sw;
	}
	/* Byte remainder (or entire copy if unaligned) */
	while (n--) *d++ = *s++;
}

void rt_memmove(void* dest, const void* src, size_t n) {
	uint8_t* d = (uint8_t*)dest;
	const uint8_t* s = (const uint8_t*)src;

	if (d < s || d >= s + n) {
		/* No overlap or dest before src: forward copy */
		if (HARE_IS_ALIGNED(d) && HARE_IS_ALIGNED(s)) {
			size_t* dw = (size_t*)d;
			const size_t* sw = (const size_t*)s;

			/* 64-byte unrolled loop */
			while (n >= 8 * HARE_WORD_SIZE) {
				dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
				dw[4] = sw[4]; dw[5] = sw[5]; dw[6] = sw[6]; dw[7] = sw[7];
				dw += 8; sw += 8;
				n -= 8 * HARE_WORD_SIZE;
			}
			/* 32-byte unrolled (4 words) */
			while (n >= 4 * HARE_WORD_SIZE) {
				dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
				dw += 4; sw += 4;
				n -= 4 * HARE_WORD_SIZE;
			}
			/* Single word loop */
			while (n >= HARE_WORD_SIZE) {
				*dw++ = *sw++;
				n -= HARE_WORD_SIZE;
			}
			d = (uint8_t*)dw;
			s = (const uint8_t*)sw;
		}
		while (n--) *d++ = *s++;
	} else {
		/* Overlap with dest after src: backward copy */
		d += n;
		s += n;

		if (HARE_IS_ALIGNED(d) && HARE_IS_ALIGNED(s)) {
			size_t* dw = (size_t*)d;
			const size_t* sw = (const size_t*)s;

			/* 64-byte unrolled backward */
			while (n >= 8 * HARE_WORD_SIZE) {
				dw -= 8; sw -= 8;
				dw[7] = sw[7]; dw[6] = sw[6]; dw[5] = sw[5]; dw[4] = sw[4];
				dw[3] = sw[3]; dw[2] = sw[2]; dw[1] = sw[1]; dw[0] = sw[0];
				n -= 8 * HARE_WORD_SIZE;
			}
			/* 32-byte unrolled backward */
			while (n >= 4 * HARE_WORD_SIZE) {
				dw -= 4; sw -= 4;
				dw[3] = sw[3]; dw[2] = sw[2]; dw[1] = sw[1]; dw[0] = sw[0];
				n -= 4 * HARE_WORD_SIZE;
			}
			/* Single word backward */
			while (n >= HARE_WORD_SIZE) {
				*--dw = *--sw;
				n -= HARE_WORD_SIZE;
			}
			d = (uint8_t*)dw;
			s = (const uint8_t*)sw;
		}
		while (n--) *--d = *--s;
	}
}

void rt_memset(void* dest, int c, size_t n) {
	uint8_t* d = (uint8_t*)dest;
	uint8_t val = (uint8_t)c;

	/* Build word pattern: 0xAB -> 0xABABABABABABABAB */
	size_t pattern = val;
	pattern |= pattern << 8;
	pattern |= pattern << 16;
#if HARE_IS_64BIT
	pattern |= pattern << 32;
#endif

	if (HARE_IS_ALIGNED(d)) {
		size_t* dw = (size_t*)d;

		/* 64-byte unrolled loop (8 words) - SIMD-friendly */
		while (n >= 8 * HARE_WORD_SIZE) {
			dw[0] = pattern; dw[1] = pattern; dw[2] = pattern; dw[3] = pattern;
			dw[4] = pattern; dw[5] = pattern; dw[6] = pattern; dw[7] = pattern;
			dw += 8;
			n -= 8 * HARE_WORD_SIZE;
		}
		/* 32-byte unrolled (4 words) */
		while (n >= 4 * HARE_WORD_SIZE) {
			dw[0] = pattern; dw[1] = pattern; dw[2] = pattern; dw[3] = pattern;
			dw += 4;
			n -= 4 * HARE_WORD_SIZE;
		}
		/* Single word loop */
		while (n >= HARE_WORD_SIZE) {
			*dw++ = pattern;
			n -= HARE_WORD_SIZE;
		}
		d = (uint8_t*)dw;
	}
	/* Byte remainder */
	while (n--) *d++ = val;
}

int rt_strcmp(hare_str a, hare_str b) {
	if (a.len != b.len) return 0;

	const uint8_t* pa = a.data;
	const uint8_t* pb = b.data;
	size_t n = a.len;

	/* Word-aligned fast path with unrolling */
	if (HARE_IS_ALIGNED(pa) && HARE_IS_ALIGNED(pb)) {
		const size_t* wa = (const size_t*)pa;
		const size_t* wb = (const size_t*)pb;

		/* 64-byte unrolled comparison (8 words) - SIMD-friendly */
		while (n >= 8 * HARE_WORD_SIZE) {
			if (wa[0] != wb[0] || wa[1] != wb[1] ||
			    wa[2] != wb[2] || wa[3] != wb[3] ||
			    wa[4] != wb[4] || wa[5] != wb[5] ||
			    wa[6] != wb[6] || wa[7] != wb[7]) return 0;
			wa += 8; wb += 8;
			n -= 8 * HARE_WORD_SIZE;
		}
		/* 32-byte unrolled (4 words) */
		while (n >= 4 * HARE_WORD_SIZE) {
			if (wa[0] != wb[0] || wa[1] != wb[1] ||
			    wa[2] != wb[2] || wa[3] != wb[3]) return 0;
			wa += 4; wb += 4;
			n -= 4 * HARE_WORD_SIZE;
		}
		/* Single word comparison */
		while (n >= HARE_WORD_SIZE) {
			if (*wa++ != *wb++) return 0;
			n -= HARE_WORD_SIZE;
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

/* ==========================================================================
 * System calls
 * ========================================================================== */

#if defined(__linux__) && defined(__x86_64__)
#define SYS_read  0
#define SYS_write 1
#define SYS_exit  60
static inline uint64_t rt_syscall1(uint64_t n, uint64_t a1) {
	uint64_t ret;
	__asm__ volatile (
		"syscall"
		: "=a"(ret)
		: "a"(n), "D"(a1)
		: "rcx", "r11", "memory"
	);
	return ret;
}
static inline uint64_t rt_syscall3(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3) {
	uint64_t ret;
	__asm__ volatile (
		"syscall"
		: "=a"(ret)
		: "a"(n), "D"(a1), "S"(a2), "d"(a3)
		: "rcx", "r11", "memory"
	);
	return ret;
}

#elif defined(__linux__) && defined(__aarch64__)  // arm64
#define SYS_read  63
#define SYS_write 64
#define SYS_exit  93
static inline uint64_t rt_syscall1(uint64_t n, uint64_t a1) {
	register uint64_t x8 __asm__("x8") = n;
	register uint64_t x0 __asm__("x0") = a1;
	__asm__ volatile (
		"svc #0"
		: "+r"(x0)
		: "r"(x8)
		: "memory"
	);
	return x0;
}
static inline uint64_t rt_syscall3(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3) {
	register uint64_t x8 __asm__("x8") = n;
	register uint64_t x0 __asm__("x0") = a1;
	register uint64_t x1 __asm__("x1") = a2;
	register uint64_t x2 __asm__("x2") = a3;
	__asm__ volatile (
		"svc #0"
		: "+r"(x0)
		: "r"(x8), "r"(x1), "r"(x2)
		: "memory"
	);
	return x0;
}

#elif defined(__riscv) && (__riscv_xlen == 64)  // riscv64
#define SYS_read  63
#define SYS_write 64
#define SYS_exit  93
static inline uint64_t rt_syscall1(uint64_t n, uint64_t a1) {
	register uint64_t a7 __asm__("a7") = n;
	register uint64_t a0 __asm__("a0") = a1;
	__asm__ volatile (
		"ecall"
		: "+r"(a0)
		: "r"(a7)
		: "memory"
	);
	return a0;
}
static inline uint64_t rt_syscall3(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3) {
	register uint64_t a7 __asm__("a7") = n;
	register uint64_t a0 __asm__("a0") = a1;
	register uint64_t a1_reg __asm__("a1") = a2;
	register uint64_t a2_reg __asm__("a2") = a3;
	__asm__ volatile (
		"ecall"
		: "+r"(a0)
		: "r"(a7), "r"(a1_reg), "r"(a2_reg)
		: "memory"
	);
	return a0;
}

#else  // other architecture
#define SYS_read  0
#define SYS_write 0
#define SYS_exit  0
/* Stubs for non-Linux platforms */
static inline uint64_t rt_syscall1(uint64_t n, uint64_t a1) { (void)n; (void)a1; return (uint64_t)-1; }
static inline uint64_t rt_syscall3(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3) { (void)n; (void)a1; (void)a2; (void)a3; return (uint64_t)-1; }
#endif

/* =========================================================================
 * Abort functions
 * ========================================================================== */
static inline void rt_write_stderr(hare_str s) {
	if (s.data && s.len) {
		rt_syscall3(SYS_write, 2, (uint64_t)s.data, s.len);
	}
}

/* Write to file descriptor */
int64_t rt_write(int fd, const void* buf, size_t count) {
#if defined(__linux__)
	return (int64_t)rt_syscall3(SYS_write, (uint64_t)fd, (uint64_t)buf, (uint64_t)count);
#else
	(void)fd; (void)buf; (void)count;
	return -1;
#endif
}

/* Read from file descriptor */
int64_t rt_read(int fd, void* buf, size_t count) {
#if defined(__linux__)
	return (int64_t)rt_syscall3(SYS_read, (uint64_t)fd, (uint64_t)buf, (uint64_t)count);
#else
	(void)fd; (void)buf; (void)count;
	return -1;
#endif
}

/* Exit process */
__attribute__((noreturn))
void rt_exit(int status) {
#if defined(__linux__)
	rt_syscall1(SYS_exit, (uint64_t)status);
#endif
	__builtin_trap();
}

/* Weak symbol - can be overridden by user */
__attribute__((weak, noreturn))
void rt_abort_handler(hare_str path, uint64_t line, uint64_t col, hare_str msg) {
	(void)path; (void)line; (void)col;
	rt_write_stderr(rt_abort_prefix);
	rt_write_stderr(msg);
	rt_write_stderr(rt_newline);
	rt_exit(134);  /* 128 + SIGABRT(6) */
	__builtin_trap();
}

__attribute__((noreturn))
void rt_abort(hare_str* path, uint64_t line, uint64_t col, hare_str msg) {
	hare_str p = path ? *path : (hare_str){0, 0};
	rt_abort_handler(p, line, col, msg);
	__builtin_unreachable();
}

__attribute__((noreturn))
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

/* Simple bump allocator - replace with real allocator if needed */
/* or use _c::malloc / _c::free and link to cstdlib */
static uint8_t heap[16 * 1024 * 1024];  /* 16MB static heap */
static size_t heap_used = 0;

void* rt_calloc(size_t nmemb, size_t size) {
	size_t n = nmemb * size;
	/* Align to 16 bytes */
	n = (n + 15) & ~(size_t)15;
	if (heap_used + n > sizeof(heap)) return (void*)0;
	void* p = &heap[heap_used];
	heap_used += n;
	rt_memset(p, 0, n);
	return p;
}

void* rt_malloc(size_t n) {
	return rt_calloc(1, n);
}

void rt_free(void* p) {
	/* Bump allocator doesn't free */
	(void)p;
}

void* rt_realloc(void* p, size_t n) {
	void* newp = rt_calloc(1, n);
	if (newp && p) {
		rt_memcpy(newp, p, n);
	}
	return newp;
}

void rt_ensure(rt_slice* s, size_t membsz) {
	size_t needed = s->capacity * membsz;
	if (s->data == (void*)0) {
		s->data = rt_malloc(needed);
	} else {
		void* newdata = rt_malloc(needed);
		if (newdata) {
			rt_memcpy(newdata, s->data, s->length * membsz);
			s->data = newdata;
		}
	}
}

void rt_unensure(rt_slice* s, size_t membsz) {
	(void)s; (void)membsz;
}

/* ==========================================================================
 * Init/Fini handlers
 * ========================================================================== */

void rt_init(void) {
	if (__start_hare_init && __stop_hare_init) {
		for (hare_init_fn* fn = __start_hare_init; fn < __stop_hare_init; fn++) {
			if (*fn) (*fn)();
		}
	}
}

void rt_fini(void) {
	if (__start_hare_fini && __stop_hare_fini) {
		for (hare_init_fn* fn = __start_hare_fini; fn < __stop_hare_fini; fn++) {
			if (*fn) (*fn)();
		}
	}
}

/* ==========================================================================
 * test handler
 * ========================================================================== */

#ifdef HARE_TEST
void rt_run_tests(void) {
	if (__start_hare_test && __stop_hare_test) {
		for (hare_init_fn* fn = __start_hare_test; fn < __stop_hare_test; fn++) {
			if (*fn) (*fn)();
		}
	}
}
#endif


/* ==========================================================================
 * Entry point (for freestanding environments)
 * ========================================================================== */

// This is defined when the transpiler encounters "export fn main() void = {..."
extern void _main(void);

// Freestanding: use this directly for embedded
// (`cc -DHARE_TEST ...` runs tests ONLY)
__attribute__((used))
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

// Hosted: default C entrypoint
__attribute__((weak))
int main(void) {
	rt_start_c();
	return 0;
}

// manually define _start for `cc ... -nostdlib -ffreestanding`
// Uses naked + inline asm to ensure proper stack alignment (16-byte per ABI)
#if defined(__x86_64__)
__attribute__((weak, naked, noreturn))
void _start(void) {
	__asm__ volatile (
		"xorl %%ebp, %%ebp\n"      // Clear frame pointer (ABI requirement)
		"andq $-16, %%rsp\n"       // Align stack to 16 bytes
		"call rt_start_c\n"
		"movl %%eax, %%edi\n"      // Exit code from rt_start_c
		"movl $60, %%eax\n"        // SYS_exit
		"syscall\n"
		"ud2\n"
		::: "memory"
	);
}
#elif defined(__aarch64__)
__attribute__((weak, naked, noreturn))
void _start(void) {
	__asm__ volatile (
		"mov x29, #0\n"            // Clear frame pointer
		"mov x30, #0\n"            // Clear link register
		"and sp, sp, #-16\n"       // Align stack to 16 bytes
		"bl rt_start_c\n"
		"mov x8, #93\n"            // SYS_exit
		"svc #0\n"
		::: "memory"
	);
}
#elif defined(__riscv) && (__riscv_xlen == 64)
__attribute__((weak, naked, noreturn))
void _start(void) {
	__asm__ volatile (
		"li fp, 0\n"               // Clear frame pointer
		"li ra, 0\n"               // Clear return address
		"andi sp, sp, -16\n"       // Align stack to 16 bytes
		"call rt_start_c\n"
		"li a7, 93\n"              // SYS_exit
		"ecall\n"
		::: "memory"
	);
}
#else
__attribute__((weak, noreturn))
void _start(void) {
	rt_start_c();
	rt_exit(0);
}
#endif

/* Freestanding compatibility - weak symbols for -nostdlib -ffreestanding builds.
 * The compiler emits implicit calls to memcpy/memmove/memset for struct copies,
 * array initialization, etc. (ABI requirement, not affected by -fno-builtin). */
__attribute__((weak, used))
void* memcpy(void* dest, const void* src, size_t n) { rt_memcpy(dest, src, n); return dest; }
__attribute__((weak, used))
void* memmove(void* dest, const void* src, size_t n) { rt_memmove(dest, src, n); return dest; }
__attribute__((weak, used))
void* memset(void* dest, int val, size_t n) { rt_memset(dest, (uint8_t)val, n); return dest; }

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
	if (s.len == 0 || s.data == (uint8_t*)0) {
		return (__hare_strings_dup_result){ .tag = 0U, .value._str = (hare_str){ (uint8_t*)0, 0 } };
	}
	uint8_t* copy = (uint8_t*)rt_malloc(s.len);
	if (copy == (uint8_t*)0) {
		return (__hare_strings_dup_result){ .tag = HARE_ERROR_TAG_BASE + 1U };
	}
	rt_memcpy(copy, s.data, s.len);
	return (__hare_strings_dup_result){ .tag = 0U, .value._str = (hare_str){ copy, s.len } };
}
