/* Test harness for 052_nd_item2_basic.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "052_nd_item2_basic.hpp"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

extern int psycl_nd_item2_basic(psycl_queue_handle_t queue,
		size_t global_0, size_t global_1,
		size_t local_0, size_t local_1,
		psycl_buffer_handle_t output,
		size_t width, size_t height,
		psycl_buffer_handle_t error);

int main(void) {
	const size_t width = 16;
	const size_t height = 8;
	const size_t local_0 = 4;
	const size_t local_1 = 4;
	const size_t N = width * height;
	bool correct = false;
	int status = PSYCL_SUCCESS;

	status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) {
		return 1;
	}

	psycl_queue_handle_t queue = psycl_get_default_queue();
	if (!queue) {
		psycl_runtime_fini();
		return 1;
	}

	uint32_t* output = (uint32_t*)malloc(N * sizeof(uint32_t));
	psycl_buffer_handle_t buf_out = NULL;

	PSYCL_TEST_CHECK_PTR(output);

	status = psycl_buffer_create_u32(&buf_out, N);
	PSYCL_TEST_CHECK(status);

	status = psycl_nd_item2_basic(queue, width, height, local_0, local_1,
		buf_out, width, height, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_u32(buf_out, output, N);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			size_t idx = y * width + x;
			uint32_t expected = (uint32_t)idx
				+ (uint32_t)(x % local_0)
				+ (uint32_t)(y % local_1);
			if (output[idx] != expected) {
				correct = false;
				break;
			}
		}
		if (!correct) break;
	}

cleanup:
	if (buf_out) psycl_buffer_destroy_u32(buf_out);
	free(output);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
