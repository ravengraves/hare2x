/* Test harness for 002_saxpy.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_saxpy(psycl_queue_handle_t queue, size_t global_0,
                           float alpha, psycl_buffer_handle_t x,
                           psycl_buffer_handle_t y, psycl_buffer_handle_t result, size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 1024;
    const float alpha = 2.5f;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* x = (float*)malloc(N * sizeof(float));
    float* y = (float*)malloc(N * sizeof(float));
    float* result = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_x = NULL;
    psycl_buffer_handle_t buf_y = NULL;
    psycl_buffer_handle_t buf_result = NULL;

    if (!x || !y || !result) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_x, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_y, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_result, N);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) {
        x[i] = (float)i;
        y[i] = (float)(i * 2);
        result[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_x, x, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_y, y, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_result, result, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_saxpy(queue, N, alpha, buf_x, buf_y, buf_result, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_read_f32(buf_result, result, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N; i++) {
        float expected = alpha * x[i] + y[i];
        if (fabsf(result[i] - expected) > 1e-5f) { correct = false; break; }
    }

cleanup:
    if (buf_x) psycl_buffer_destroy_f32(buf_x);
    if (buf_y) psycl_buffer_destroy_f32(buf_y);
    if (buf_result) psycl_buffer_destroy_f32(buf_result);
    free(x);
    free(y);
    free(result);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
