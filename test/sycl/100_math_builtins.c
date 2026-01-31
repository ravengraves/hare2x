/* Test harness for 100_math_builtins.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_math_comprehensive(psycl_queue_handle_t queue, size_t global_0,
                                        psycl_buffer_handle_t input, psycl_buffer_handle_t output,
                                        size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 128;
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
        input[i] = (float)(i + 1) * 0.05f;  /* Range: 0.05 to 6.4 */
        output[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_input, input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_math_comprehensive(queue, N, buf_input, buf_output, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Verify no NaN or extreme values */
    status = psycl_buffer_read_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N && correct; i++) {
        if (output[i] != output[i]) correct = false;  /* NaN check */
        if (output[i] > 1e10f || output[i] < -1e10f) correct = false;
    }

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(input);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
