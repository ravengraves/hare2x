/* Test harness for 011_atomic_histogram.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

extern int psycl_histogram(psycl_queue_handle_t queue, size_t global_0,
                               psycl_buffer_handle_t values, psycl_buffer_handle_t histogram,
                               size_t N, size_t num_bins, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 1024;
    const size_t num_bins = 10;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* values = (float*)malloc(N * sizeof(float));
    uint32_t* histogram = (uint32_t*)malloc(num_bins * sizeof(uint32_t));
    psycl_buffer_handle_t buf_values = NULL;
    psycl_buffer_handle_t buf_histogram = NULL;

    if (!values || !histogram) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_values, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_u32(&buf_histogram, num_bins);
    PSYCL_TEST_CHECK(status);



    /* Initialize values in range [0, 1) */
    for (size_t i = 0; i < N; i++) {
        values[i] = (float)i / (float)N;
    }
    memset(histogram, 0, num_bins * sizeof(uint32_t));

    status = psycl_buffer_write_f32(buf_values, values, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_u32(buf_histogram, histogram, num_bins);
    PSYCL_TEST_CHECK(status);



    status = psycl_histogram(queue, N, buf_values, buf_histogram, N, num_bins, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_read_u32(buf_histogram, histogram, num_bins);
    PSYCL_TEST_CHECK(status);

    /* Verify: sum of histogram should equal N */
    uint32_t sum = 0;
    for (size_t i = 0; i < num_bins; i++) {
        sum += histogram[i];
    }
    correct = (sum == N);

cleanup:
    if (buf_values) psycl_buffer_destroy_f32(buf_values);
    if (buf_histogram) psycl_buffer_destroy_u32(buf_histogram);
    free(values);
    free(histogram);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
