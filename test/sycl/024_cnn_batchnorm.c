/* Test harness for 024_cnn_batchnorm.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_batchnorm2d(psycl_queue_handle_t queue, size_t global_0,
    psycl_buffer_handle_t input, psycl_buffer_handle_t output,
    psycl_buffer_handle_t gamma, psycl_buffer_handle_t beta,
    psycl_buffer_handle_t mean, psycl_buffer_handle_t var,
    size_t channels, size_t height, size_t width, float epsilon, psycl_buffer_handle_t error);

int main(void) {
    const size_t channels = 2, height = 4, width = 4;
    const size_t N = channels * height * width;
    const float epsilon = 1e-5f;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* input = (float*)malloc(N * sizeof(float));
    float* output = (float*)malloc(N * sizeof(float));
    float* gamma = (float*)malloc(channels * sizeof(float));
    float* beta = (float*)malloc(channels * sizeof(float));
    float* mean = (float*)malloc(channels * sizeof(float));
    float* var = (float*)malloc(channels * sizeof(float));
    psycl_buffer_handle_t buf_input = NULL;
    psycl_buffer_handle_t buf_output = NULL;
    psycl_buffer_handle_t buf_gamma = NULL;
    psycl_buffer_handle_t buf_beta = NULL;
    psycl_buffer_handle_t buf_mean = NULL;
    psycl_buffer_handle_t buf_var = NULL;

    if (!input || !output || !gamma || !beta || !mean || !var) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_output, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_gamma, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_beta, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_mean, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_var, channels);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) input[i] = (float)i;
    for (size_t c = 0; c < channels; c++) {
        gamma[c] = 1.0f;
        beta[c] = 0.0f;
        mean[c] = 0.0f;
        var[c] = 1.0f;
    }
    for (size_t i = 0; i < N; i++) output[i] = 0.0f;

    status = psycl_buffer_write_f32(buf_input, input, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_gamma, gamma, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_beta, beta, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_mean, mean, channels);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_var, var, channels);
    PSYCL_TEST_CHECK(status);



    int result = psycl_batchnorm2d(queue, N,
        buf_input, buf_output, buf_gamma, buf_beta, buf_mean, buf_var,
        channels, height, width, epsilon, NULL);

    PSYCL_TEST_CHECK(result);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* With gamma=1, beta=0, mean=0, var=1: output = (input - 0) / sqrt(1 + eps) */
    status = psycl_buffer_read_f32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    float scale = 1.0f / sqrtf(1.0f + epsilon);
    for (size_t i = 0; i < N && correct; i++) {
        float expected = input[i] * scale;
        if (fabsf(output[i] - expected) > 1e-4f) correct = false;
    }

cleanup:
    if (buf_input) psycl_buffer_destroy_f32(buf_input);
    if (buf_output) psycl_buffer_destroy_f32(buf_output);
    if (buf_gamma) psycl_buffer_destroy_f32(buf_gamma);
    if (buf_beta) psycl_buffer_destroy_f32(buf_beta);
    if (buf_mean) psycl_buffer_destroy_f32(buf_mean);
    if (buf_var) psycl_buffer_destroy_f32(buf_var);
    free(input);
    free(output);
    free(gamma);
    free(beta);
    free(mean);
    free(var);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
