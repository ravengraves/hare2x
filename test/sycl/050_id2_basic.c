/* Test harness for 050_id2_basic.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "050_id2_basic.hpp"
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
	const size_t width = 16;
	const size_t height = 8;
	const size_t count = width * height;
	bool correct = false;
	int status = PSYCL_SUCCESS;

	status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

	psycl_queue_handle_t queue = psycl_get_default_queue();
	if (!queue) { psycl_runtime_fini(); return 1; }

	uint32_t* output = (uint32_t*)malloc(count * sizeof(uint32_t));
	psycl_buffer_handle_t buf_output = NULL;

	PSYCL_TEST_CHECK_PTR(output);

	for (size_t i = 0; i < count; i++) {
		output[i] = 0u;
	}

	status = psycl_buffer_create_u32(&buf_output, count);
	PSYCL_TEST_CHECK(status);


	status = psycl_buffer_write_u32(buf_output, output, count);
	PSYCL_TEST_CHECK(status);


	status = psycl_fill2d(queue, width, height, buf_output, width, height, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_u32(buf_output, output, count);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t y = 0; y < height && correct; y++) {
		for (size_t x = 0; x < width; x++) {
			size_t idx = y * width + x;
			uint32_t expected = (uint32_t)(y * 1000u + x);
			if (output[idx] != expected) {
				correct = false;
				break;
			}
		}
	}

cleanup:
	if (buf_output) psycl_buffer_destroy_u32(buf_output);
	free(output);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
