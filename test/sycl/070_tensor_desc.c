/* Test harness for 070_tensor_desc.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "070_tensor_desc.hpp"

#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

extern int psycl_tensor_add(psycl_queue_handle_t queue, size_t global_0,
				psycl_buffer_handle_t a, psycl_buffer_handle_t b,
				psycl_buffer_handle_t out,
				struct tensor_desc a_desc,
				struct tensor_desc b_desc,
				struct tensor_desc out_desc,
				psycl_buffer_handle_t error);

int main(void) {
	const size_t width = 4;
	const size_t height = 3;
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

	float* a = (float*)malloc(N * sizeof(float));
	float* b = (float*)malloc(N * sizeof(float));
	float* out = (float*)malloc(N * sizeof(float));
	psycl_buffer_handle_t buf_a = NULL;
	psycl_buffer_handle_t buf_b = NULL;
	psycl_buffer_handle_t buf_out = NULL;

	if (!a || !b || !out) {
		goto cleanup;
	}

	status = psycl_buffer_create_f32(&buf_a, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_b, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_out, N);
	PSYCL_TEST_CHECK(status);



	for (size_t i = 0; i < N; i++) {
		a[i] = (float)i;
		b[i] = (float)(100 + i);
		out[i] = 0.0f;
	}

	status = psycl_buffer_write_f32(buf_a, a, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_write_f32(buf_b, b, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_write_f32(buf_out, out, N);
	PSYCL_TEST_CHECK(status);



	struct tensor_desc a_desc = {
		.base_offset = 0,
		.stride0 = width,
		.stride1 = 1,
		.dim0 = height,
		.dim1 = width
	};
	struct tensor_desc b_desc = a_desc;
	struct tensor_desc out_desc = a_desc;

	status = psycl_tensor_add(queue, N, buf_a, buf_b, buf_out,
		a_desc, b_desc, out_desc, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_f32(buf_out, out, N);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t i = 0; i < N; i++) {
		float expected = a[i] + b[i];
		if (fabsf(out[i] - expected) > 1e-5f) {
			correct = false;
			break;
		}
	}

cleanup:
	if (buf_a) psycl_buffer_destroy_f32(buf_a);
	if (buf_b) psycl_buffer_destroy_f32(buf_b);
	if (buf_out) psycl_buffer_destroy_f32(buf_out);
	free(a);
	free(b);
	free(out);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
