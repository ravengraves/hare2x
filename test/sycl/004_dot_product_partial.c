/* Test harness for 004_dot_product_partial.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_dot_partial(psycl_queue_handle_t queue, size_t global_0,
                                 psycl_buffer_handle_t a, psycl_buffer_handle_t b,
                                 psycl_buffer_handle_t partial, size_t N, psycl_buffer_handle_t error);

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
    float* partial = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_a = NULL;
    psycl_buffer_handle_t buf_b = NULL;
    psycl_buffer_handle_t buf_partial = NULL;

    if (!a || !b || !partial) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_a, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_b, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_partial, N);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) {
        a[i] = (float)i;
        b[i] = (float)(i + 1);
        partial[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_a, a, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_b, b, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_partial, partial, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_dot_partial(queue, N, buf_a, buf_b, buf_partial, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_read_f32(buf_partial, partial, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N; i++) {
        float expected = a[i] * b[i];
        if (fabsf(partial[i] - expected) > 1e-5f) { correct = false; break; }
    }

cleanup:
    if (buf_a) psycl_buffer_destroy_f32(buf_a);
    if (buf_b) psycl_buffer_destroy_f32(buf_b);
    if (buf_partial) psycl_buffer_destroy_f32(buf_partial);
    free(a);
    free(b);
    free(partial);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
