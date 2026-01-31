/* Test harness for 040_match_nullable.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "040_match_nullable.hpp"
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    const size_t N = 16;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    uint32_t* output = (uint32_t*)malloc(N * sizeof(uint32_t));
    psycl_buffer_handle_t buf_output = NULL;

    PSYCL_TEST_CHECK_PTR(output);

    for (size_t i = 0; i < N; i++) {
        output[i] = 0u;
    }

    status = psycl_buffer_create_u32(&buf_output, N);
    PSYCL_TEST_CHECK(status);


    status = psycl_buffer_write_u32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);


    status = psycl_match_nullable(queue, N, buf_output, N, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);


    status = psycl_buffer_read_u32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    correct = true;
    for (size_t i = 0; i < N; i++) {
        uint32_t expected = (i % 2 == 0) ? (uint32_t)i : 0u;
        if (output[i] != expected) {
            correct = false;
            break;
        }
    }

cleanup:
    if (buf_output) psycl_buffer_destroy_u32(buf_output);
    free(output);
    psycl_runtime_fini();


    return correct ? 0 : 1;
}
