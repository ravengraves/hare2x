/* Test harness for 030_array_simple.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_array_copy(psycl_queue_handle_t queue, size_t global_0,
                                psycl_buffer_handle_t output, size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 4;  /* Kernel uses fixed 4-element array */
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* output = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_output = NULL;
    if (!output) { psycl_runtime_fini(); return 1; }

    status = psycl_buffer_create_f32(&buf_output, N);
    PSYCL_TEST_CHECK(status);


    for (size_t i = 0; i < N; i++) output[i] = 0.0f;

    status = psycl_buffer_write_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);


    status = psycl_array_copy(queue, N, buf_output, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Kernel creates [1, 2, 3, 4] and copies to output */
    status = psycl_buffer_read_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    float expected[] = {1.0f, 2.0f, 3.0f, 4.0f};
    for (size_t i = 0; i < N && correct; i++) {
        if (fabsf(output[i] - expected[i]) > 1e-5f) correct = false;
    }

cleanup:
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
