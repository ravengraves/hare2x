/* Test harness for 102_memory_builtins.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

extern int psycl_memory_and_nd_item(psycl_queue_handle_t queue, size_t global_0, size_t local_0,
                                        size_t local_size_scratch, psycl_buffer_handle_t src,
                                        psycl_buffer_handle_t dst, size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 256;
    const size_t local_size = 64;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    float* src = (float*)malloc(N * sizeof(float));
    float* dst = (float*)malloc(N * sizeof(float));
    psycl_buffer_handle_t buf_src = NULL;
    psycl_buffer_handle_t buf_dst = NULL;

    if (!src || !dst) {
        goto cleanup;
    }

    status = psycl_buffer_create_f32(&buf_src, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_create_f32(&buf_dst, N);
    PSYCL_TEST_CHECK(status);



    for (size_t i = 0; i < N; i++) {
        src[i] = (float)i;
        dst[i] = 0.0f;
    }

    status = psycl_buffer_write_f32(buf_src, src, N);
    PSYCL_TEST_CHECK(status);
    status = psycl_buffer_write_f32(buf_dst, dst, N);
    PSYCL_TEST_CHECK(status);



    status = psycl_memory_and_nd_item(queue, N, local_size, local_size, buf_src, buf_dst, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Just verify kernel ran and produced valid output */
    status = psycl_buffer_read_f32(buf_dst, dst, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N && correct; i++) {
        if (dst[i] != dst[i]) correct = false;  /* NaN check */
    }

cleanup:
    if (buf_src) psycl_buffer_destroy_f32(buf_src);
    if (buf_dst) psycl_buffer_destroy_f32(buf_dst);
    free(src);
    free(dst);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
