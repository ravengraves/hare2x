/* Test harness for 023_cnn_maxpool2d.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_maxpool2d(psycl_queue_handle_t queue, size_t global_0,
    psycl_buffer_handle_t input, psycl_buffer_handle_t output,
    size_t channels, size_t in_height, size_t in_width,
    size_t out_height, size_t out_width, size_t pool_h, size_t pool_w, size_t stride, psycl_buffer_handle_t error);

int main(void) {
    const size_t channels = 1;
    const size_t in_h = 4, in_w = 4;
    const size_t pool_h = 2, pool_w = 2;
    const size_t stride = 2;
    const size_t out_h = in_h / stride, out_w = in_w / stride;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    size_t input_count = channels * in_h * in_w;
    size_t output_count = channels * out_h * out_w;
    float* input = (float*)malloc(input_count * sizeof(float));
    float* output = (float*)malloc(output_count * sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_output = NULL;

    if (!input || !output) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, input_count);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, output_count);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < input_count; i++) input[i] = (float)i;
    for (size_t i = 0; i < output_count; i++) output[i] = 0.0f;

    status = psycl_buffer_write_f32(buf_input, input, input_count);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, output_count);
    PSYCL_TEST_CHECK(status);



    int result = psycl_maxpool2d(queue, output_count,
        buf_input, buf_output, channels, in_h, in_w, out_h, out_w, pool_h, pool_w, stride, NULL);

    PSYCL_TEST_CHECK(result);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Verify: max pooling picks max from each 2x2 region */
    status = psycl_buffer_read_f32(buf_output, output, output_count);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t oy = 0; oy < out_h && correct; oy++) {
        for (size_t ox = 0; ox < out_w && correct; ox++) {
            float max_val = -1e30f;
            for (size_t py = 0; py < pool_h; py++) {
                for (size_t px = 0; px < pool_w; px++) {
                    size_t iy = oy * stride + py;
                    size_t ix = ox * stride + px;
                    if (input[iy * in_w + ix] > max_val) max_val = input[iy * in_w + ix];
                }
            }
            if (fabsf(output[oy * out_w + ox] - max_val) > 1e-5f) correct = false;
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
