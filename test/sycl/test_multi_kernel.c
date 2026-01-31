/* Test harness for test_multi_kernel.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_add(psycl_queue_handle_t queue, size_t global_0,
                         psycl_buffer_handle_t a, psycl_buffer_handle_t b,
                         psycl_buffer_handle_t c, size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 1024;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* a = (float*)malloc(N * sizeof(float));
    float* b = (float*)malloc(N * sizeof(float));
    float* c = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_a = NULL;
    psycl_buffer_handle_t buf_b = NULL;
    psycl_buffer_handle_t buf_c = NULL;

    if (!a || !b || !c) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_a, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_b, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_c, N);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) {
        a[i] = (float)i;
        b[i] = (float)(i * 2);
        c[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_a, a, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_b, b, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_c, c, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_add(queue, N, buf_a, buf_b, buf_c, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_read_f32(buf_c, c, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N; i++) {
        if (fabsf(c[i] - (a[i] + b[i])) > 1e-5f) { correct = false; break; }
    }

cleanup:
    if (buf_a) psycl_buffer_destroy_f32(buf_a);
    if (buf_b) psycl_buffer_destroy_f32(buf_b);
    if (buf_c) psycl_buffer_destroy_f32(buf_c);
    free(a);
    free(b);
    free(c);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
