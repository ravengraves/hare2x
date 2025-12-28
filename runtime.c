/* Hare Runtime Library for C11 */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>

void* __hare_malloc(size_t size) {
    void* p = malloc(size);
    if (!p && size > 0) {
        fprintf(stderr, "hare: out of memory\n");
        abort();
    }
    return p;
}

void* __hare_realloc(void* ptr, size_t size) {
    void* p = realloc(ptr, size);
    if (!p && size > 0) {
        fprintf(stderr, "hare: out of memory\n");
        abort();
    }
    return p;
}

void* __hare_calloc(size_t nmemb, size_t size) {
    void* p = calloc(nmemb, size);
    if (!p && nmemb > 0 && size > 0) {
        fprintf(stderr, "hare: out of memory\n");
        abort();
    }
    return p;
}

void __hare_free(void* ptr) {
    free(ptr);
}

void __hare_abort(const char* msg) {
    fprintf(stderr, "hare: abort: %s\n", msg ? msg : "(no message)");
    abort();
}
