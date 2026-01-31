/* Test harness for 020_cnn_conv2d_simple.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_conv2d_simple(psycl_queue_handle_t queue, size_t global_0,
    psycl_buffer_handle_t input, psycl_buffer_handle_t kernel, psycl_buffer_handle_t output,
    size_t in_height, size_t in_width, size_t out_height, size_t out_width,
    size_t kernel_h, size_t kernel_w, size_t stride, size_t padding, psycl_buffer_handle_t error);

int main(void) {
    const size_t in_h = 8, in_w = 8;
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

    float* input = (float*)malloc(in_h * in_w * sizeof(float));
    float* kernel = (float*)malloc(k_h * k_w * sizeof(float));
    float* output = (float*)malloc(out_h * out_w * sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_kernel = NULL;
    psycl_buffer_handle_t buf_output = NULL;

    if (!input || !kernel || !output) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, in_h * in_w);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_kernel, k_h * k_w);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, out_h * out_w);
    PSYCL_TEST_CHECK(status);



    /* Initialize input with sequential values, kernel with 1s */
    for (size_t i = 0; i < in_h * in_w; i++) input[i] = (float)i;
    for (size_t i = 0; i < k_h * k_w; i++) kernel[i] = 1.0f;
    for (size_t i = 0; i < out_h * out_w; i++) output[i] = 0.0f;

    status = psycl_buffer_write_f32(buf_input, input, in_h * in_w);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_kernel, kernel, k_h * k_w);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, out_h * out_w);
    PSYCL_TEST_CHECK(status);



    int result = psycl_conv2d_simple(queue, out_h * out_w,
        buf_input, buf_kernel, buf_output, in_h, in_w, out_h, out_w, k_h, k_w, stride, padding, NULL);

    PSYCL_TEST_CHECK(result);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Verify: with all-ones kernel, output should be sum of 3x3 region */
    status = psycl_buffer_read_f32(buf_output, output, out_h * out_w);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t oy = 0; oy < out_h && correct; oy++) {
        for (size_t ox = 0; ox < out_w && correct; ox++) {
            float expected = 0.0f;
            for (size_t ky = 0; ky < k_h; ky++) {
                for (size_t kx = 0; kx < k_w; kx++) {
                    expected += input[(oy + ky) * in_w + (ox + kx)];
                }
            }
            if (fabsf(output[oy * out_w + ox] - expected) > 1e-4f) correct = false;
        }
    }

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_kernel) psycl_buffer_destroy_f32(buf_kernel);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    free(input);
    free(kernel);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
