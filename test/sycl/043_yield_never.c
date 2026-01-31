/* Test harness for 043_yield_never.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "043_yield_never.hpp"
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    psycl_error_t err = psycl_error_none();
    const size_t N = 2;
    bool correct = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }

    uint32_t* output = (uint32_t*)malloc(N * sizeof(uint32_t));
    psycl_buffer_handle_t buf_output = NULL;
    psycl_buffer_handle_t buf_error = NULL;

    PSYCL_TEST_CHECK_PTR(output);

    status = psycl_buffer_create_u32(&buf_output, N);
    PSYCL_TEST_CHECK(status);

    status = psycl_error_buffer_create(&buf_error);
    PSYCL_TEST_CHECK(status);

    status = psycl_buffer_write_u32(buf_output, output, N);
    PSYCL_TEST_CHECK(status);

    status = psycl_error_buffer_reset(buf_error);
    PSYCL_TEST_CHECK(status);

    status = psycl_yield_never(queue, N, buf_output, N, buf_error);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    err = psycl_error_buffer_fetch(buf_error);
	if (err.code == 2u && err.loc != 0u) {
		correct = true;
	} else if (!psycl_error_is_ok(err)) {
		goto cleanup;
	}

cleanup:
    if (buf_output) psycl_buffer_destroy_u32(buf_output);
    if (buf_error) psycl_error_buffer_destroy(buf_error);
    free(output);
    psycl_runtime_fini();

    return correct ? 0 : 1;
}
