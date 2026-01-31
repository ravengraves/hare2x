/* Test harness for 054_tiled_transpose.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "054_tiled_transpose.hpp"

#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

extern int psycl_tiled_transpose(psycl_queue_handle_t queue,
		size_t global_0, size_t global_1,
		size_t local_0, size_t local_1,
		size_t local_size_tile,
		psycl_buffer_handle_t input,
		psycl_buffer_handle_t output,
		size_t width, size_t height,
		psycl_buffer_handle_t error);

int main(void) {
	const size_t width = 8;
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

	float* input = (float*)malloc(N * sizeof(float));
	float* output = (float*)malloc(N * sizeof(float));
	psycl_buffer_handle_t buf_in = NULL;
	psycl_buffer_handle_t buf_out = NULL;

	if (!input || !output) {
		goto cleanup;
	}

	status = psycl_buffer_create_f32(&buf_in, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_out, N);
	PSYCL_TEST_CHECK(status);



	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			input[y * width + x] = (float)(y * width + x);
			output[y * width + x] = 0.0f;
		}
	}

	status = psycl_buffer_write_f32(buf_in, input, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_write_f32(buf_out, output, N);
	PSYCL_TEST_CHECK(status);


	status = psycl_tiled_transpose(queue, width, height, local_0, local_1,
		local_0 * local_1, buf_in, buf_out, width, height, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_f32(buf_out, output, N);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			float expected = input[y * width + x];
			float got = output[x * height + y];
			if (fabsf(got - expected) > 1e-5f) {
				correct = false;
				break;
			}
		}
		if (!correct) break;
	}

cleanup:
	if (buf_in) psycl_buffer_destroy_f32(buf_in);
	if (buf_out) psycl_buffer_destroy_f32(buf_out);
	free(input);
	free(output);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
