/* Test harness for 012_reduction_atomic.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

extern int psycl_reduce_atomic(psycl_queue_handle_t queue, size_t global_0,
                                   psycl_buffer_handle_t input, psycl_buffer_handle_t output,
                                   size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 1024;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* input = (float*)malloc(N * sizeof(float));
    float* output = (float*)malloc(sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_output = NULL;

    if (!input || !output) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, 1);
    PSYCL_TEST_CHECK(status);



    /* Sum of 1 to N = N*(N+1)/2 when starting from 1 */
    float expected = 0.0f;
    for (size_t i = 0; i < N; i++) {
        input[i] = 1.0f;
        expected += 1.0f;
    }
    *output = 0.0f;

    status = psycl_buffer_write_f32(buf_input, input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, 1);
    PSYCL_TEST_CHECK(status);



    status = psycl_reduce_atomic(queue, N, buf_input, buf_output, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Allow some tolerance for atomic operations */
    status = psycl_buffer_read_f32(buf_output, output, 1);
    PSYCL_TEST_CHECK(status);
    correct = (*output >= expected - 1.0f && *output <= expected + 1.0f);

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(input);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
