/* Test harness for 021_cnn_conv2d_multichannel.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_conv2d_multichannel(psycl_queue_handle_t queue, size_t global_0,
    psycl_buffer_handle_t input, psycl_buffer_handle_t weights,
    psycl_buffer_handle_t bias, psycl_buffer_handle_t output,
    size_t in_channels, size_t out_channels, size_t in_height, size_t in_width,
    size_t out_height, size_t out_width, size_t kernel_h, size_t kernel_w,
    size_t stride, size_t padding, psycl_buffer_handle_t error);

int main(void) {
    const size_t in_c = 2, out_c = 2;
    const size_t in_h = 4, in_w = 4;
    const size_t k_h = 3, k_w = 3;
    const size_t stride = 1, padding = 0;
    const size_t out_h = in_h - k_h + 1;
    const size_t out_w = in_w - k_w + 1;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    size_t input_size = in_c * in_h * in_w;
    size_t weight_size = out_c * in_c * k_h * k_w;
    size_t output_size = out_c * out_h * out_w;

    float* input = (float*)malloc(input_size * sizeof(float));
    float* weights = (float*)malloc(weight_size * sizeof(float));
    float* bias = (float*)malloc(out_c * sizeof(float));
    float* output = (float*)malloc(output_size * sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_weights = NULL;
    psycl_buffer_handle_t buf_bias = NULL;
    psycl_buffer_handle_t buf_output = NULL;

    if (!input || !weights || !bias || !output) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, input_size);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_weights, weight_size);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_bias, out_c);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, output_size);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < input_size; i++) input[i] = 1.0f;
    for (size_t i = 0; i < weight_size; i++) weights[i] = 1.0f;
    for (size_t i = 0; i < out_c; i++) bias[i] = 0.0f;
    for (size_t i = 0; i < output_size; i++) output[i] = 0.0f;

    status = psycl_buffer_write_f32(buf_input, input, input_size);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_weights, weights, weight_size);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_bias, bias, out_c);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, output_size);
    PSYCL_TEST_CHECK(status);



    int result = psycl_conv2d_multichannel(queue, output_size,
        buf_input, buf_weights, buf_bias, buf_output, in_c, out_c, in_h, in_w, out_h, out_w,
        k_h, k_w, stride, padding, NULL);

    PSYCL_TEST_CHECK(result);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* With all-1 input and weights, each output = in_c * k_h * k_w = 2*3*3 = 18 */
    status = psycl_buffer_read_f32(buf_output, output, output_size);
    PSYCL_TEST_CHECK(status);

    correct = true;
    float expected = (float)(in_c * k_h * k_w);
    for (size_t i = 0; i < output_size && correct; i++) {
        if (fabsf(output[i] - expected) > 1e-3f) correct = false;
    }

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_weights) psycl_buffer_destroy_f32(buf_weights);
    if (buf_bias) psycl_buffer_destroy_f32(buf_bias);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(input);
    free(weights);
    free(bias);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
