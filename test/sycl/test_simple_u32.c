/* Test harness for test_simple_u32.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

extern int psycl_test(psycl_queue_handle_t queue, size_t global_0,
                          psycl_buffer_handle_t data, size_t N, psycl_buffer_handle_t error);

int main(void) {
    const size_t N = 256;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    uint32_t* data = (uint32_t*)malloc(N * sizeof(uint32_t));
    psycl_buffer_handle_t buf_data = NULL;
    if (!data) { psycl_runtime_fini(); return 1; }

    status = psycl_buffer_create_u32(&buf_data, N);
    PSYCL_TEST_CHECK(status);


    for (size_t i = 0; i < N; i++) data[i] = 0;

    status = psycl_buffer_write_u32(buf_data, data, N);
    PSYCL_TEST_CHECK(status);


    status = psycl_test(queue, N, buf_data, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    /* Verify: data[i] should be 0 after kernel runs */
    status = psycl_buffer_read_u32(buf_data, data, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N && correct; i++) {
        if (data[i] != 0) correct = false;
    }

cleanup:
    if (buf_data) psycl_buffer_destroy_u32(buf_data);
    free(data);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
