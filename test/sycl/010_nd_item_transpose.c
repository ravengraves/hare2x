/* Test harness for 010_nd_item_transpose.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_transpose(psycl_queue_handle_t queue, size_t global_0, size_t local_0,
                               psycl_buffer_handle_t input, psycl_buffer_handle_t output,
                               size_t rows, size_t cols, psycl_buffer_handle_t error);

int main(void) {
    const size_t rows = 32;
    const size_t cols = 32;
    const size_t N = rows * cols;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* input = (float*)malloc(N * sizeof(float));
    float* output = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_output = NULL;

    if (!input || !output) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, N);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) {
        input[i] = (float)i;
        output[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_input, input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_transpose(queue, N, 32, buf_input, buf_output, rows, cols, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_read_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    /* Verify transpose: output[col*rows+row] = input[row*cols+col] */
    correct = true;
    for (size_t row = 0; row < rows && correct; row++) {
        for (size_t col = 0; col < cols && correct; col++) {
            float expected = input[row * cols + col];
            float actual = output[col * rows + row];
            if (fabsf(actual - expected) > 1e-5f) correct = false;
        }
    }

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(input);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
