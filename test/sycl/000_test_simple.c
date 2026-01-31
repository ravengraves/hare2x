/* Test harness for 000_test_simple.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "000_test_simple.hpp"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

/* NOTE: This test is intentionally verbose; it's our sanity-check test for debugging. */
int main(void) {
    const size_t N = 1024;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    printf("Starting test...\n");

    status = psycl_runtime_init();
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_runtime_init() (%d)\n", status);
        return 1;
    }
    printf("OK: psycl_runtime_init()\n");

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) {
        printf("FAIL: psycl_get_default_queue() returned NULL\n");
        psycl_runtime_fini();
        return 1;
    }
    printf("OK: psycl_get_default_queue()\n");

    float* a = (float*)malloc(N * sizeof(float));
    float* b = (float*)malloc(N * sizeof(float));
    float* c = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_a = NULL;
    psycl_buffer_handle_t buf_b = NULL;
    psycl_buffer_handle_t buf_c = NULL;

    if (!a || !b || !c) {
        printf("FAIL: host malloc failed\n");
        goto cleanup;
    }
    printf("OK: allocations\n");

    status = psycl_buffer_create_f32(&buf_a, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_create_f32(buf_a) (%d)\n", status);
        goto cleanup;
    }
    status = psycl_buffer_create_f32(&buf_b, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_create_f32(buf_b) (%d)\n", status);
        goto cleanup;
    }
    status = psycl_buffer_create_f32(&buf_c, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_create_f32(buf_c) (%d)\n", status);
        goto cleanup;
    }

    
    for (size_t i = 0; i < N; i++) {
        a[i] = (float)i;
        b[i] = (float)(i * 2);
        c[i] = 0.0f;
    }
    printf("OK: initialized arrays\n");

    status = psycl_buffer_write_f32(buf_a, a, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_write_f32(buf_a) (%d)\n", status);
        goto cleanup;
    }
    status = psycl_buffer_write_f32(buf_b, b, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_write_f32(buf_b) (%d)\n", status);
        goto cleanup;
    }
    status = psycl_buffer_write_f32(buf_c, c, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_write_f32(buf_c) (%d)\n", status);
        goto cleanup;
    }

    printf("Launching kernel...\n");
    status = psycl_add(queue, N, buf_a, buf_b, buf_c, N, NULL);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_add() (%d)\n", status);
        goto cleanup;
    }
    printf("OK: psycl_add()\n");

    printf("Waiting for queue...\n");
    status = psycl_queue_wait(queue);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_queue_wait() (%d)\n", status);
        goto cleanup;
    }
    printf("OK: psycl_queue_wait()\n");

    status = psycl_buffer_read_f32(buf_c, c, N);
    if (status != PSYCL_SUCCESS) {
        printf("FAIL: psycl_buffer_read_f32(buf_c) (%d)\n", status);
        goto cleanup;
    }

    printf("Verifying results...\n");
    correct = true;
    for (size_t i = 0; i < N; i++) {
        if (fabsf(c[i] - (a[i] + b[i])) > 1e-5f) {
            printf("FAIL: mismatch at i=%zu (%f != %f)\n", i, c[i], a[i] + b[i]);
            correct = false;
            break;
        }
    }
    if (correct) {
        printf("OK: all values correct\n");
    }

cleanup:
    if (buf_a) psycl_buffer_destroy_f32(buf_a);
    if (buf_b) psycl_buffer_destroy_f32(buf_b);
    if (buf_c) psycl_buffer_destroy_f32(buf_c);
    free(a);
    free(b);
    free(c);
    psycl_runtime_fini();

    printf("Final result: %s\n", correct ? "PASS" : "FAIL");

    return correct ? 0 : 1;
}
