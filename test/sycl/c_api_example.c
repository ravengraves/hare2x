// Example of using the SYCL C API from plain C code
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Include the generated SYCL kernel header (which includes C API)
#include "kernel_output.sycl.hpp"

int main(void) {
    psycl_error_t err = psycl_error_none();
    const size_t N = 1024;

    // Allocate host memory
    float *h_a = (float*)malloc(N * sizeof(float));
    float *h_b = (float*)malloc(N * sizeof(float));
    float *h_c = (float*)malloc(N * sizeof(float));

    if (!h_a || !h_b || !h_c) {
        fprintf(stderr, "Failed to allocate host memory\n");
        return 1;
    }

    // Initialize input arrays
    for (size_t i = 0; i < N; i++) {
        h_a[i] = (float)i;
        h_b[i] = (float)(i * 2);
        h_c[i] = 0.0f;
    }

    // Create SYCL queue
    psycl_queue_handle_t queue;
    int status = psycl_create_queue(&queue);
    if (status != PSYCL_SUCCESS) {
        fprintf(stderr, "Failed to create SYCL queue: %d\n", status);
        free(h_a);
        free(h_b);
        free(h_c);
        return 1;
    }

    printf("SYCL queue created successfully\n");
    printf("Device info available through C++ API\n");

    // Launch kernel using C API
    // Note: In real usage, you'd need to allocate device memory first
    // This is just a demonstration of the C API interface

    // For demonstration: the actual kernel should use buffers/accessors
    // psycl_buffer_handle_t buf_a, buf_b, buf_c, buf_error;
    // psycl_error_t err = psycl_error_none();
    // psycl_buffer_create_f32(&buf_a, N);
    // psycl_buffer_create_f32(&buf_b, N);
    // psycl_buffer_create_f32(&buf_c, N);
    // psycl_buffer_write_f32(buf_a, h_a, N);
    // psycl_buffer_write_f32(buf_b, h_b, N);
    // status = psycl_vector_add(queue, N, buf_a, buf_b, buf_c, N, NULL);
    // if (status == PSYCL_SUCCESS) {
    //     status = psycl_queue_wait(queue);
    // }
    // if (status == PSYCL_SUCCESS) {
    // }
    // psycl_buffer_destroy_f32(buf_a);
    // psycl_buffer_destroy_f32(buf_b);
    // psycl_buffer_destroy_f32(buf_c);

    // Wait for completion
    status = psycl_queue_wait(queue);
    if (status != PSYCL_SUCCESS) {
        fprintf(stderr, "Queue wait failed: %d\n", status);
    }

    // Verify results
    int errors = 0;
    for (size_t i = 0; i < N && errors < 10; i++) {
        float expected = h_a[i] + h_b[i];
        if (fabsf(h_c[i] - expected) > 1e-5f) {
            fprintf(stderr, "Mismatch at %zu: expected %f, got %f\n",
                    i, expected, h_c[i]);
            errors++;
        }
    }

    if (errors == 0) {
        printf("✓ C API test passed\n");
    } else {
        printf("✗ C API test failed with %d errors\n", errors);
    }

    // Cleanup
    psycl_destroy_queue(queue);
    free(h_a);
    free(h_b);
    free(h_c);

    return (errors == 0) ? 0 : 1;
}
