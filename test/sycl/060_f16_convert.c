/* Test harness for 060_f16_convert.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "060_f16_convert.hpp"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

/* External C API functions (provided by compiled kernel) */
extern int psycl_f16_to_f32(psycl_queue_handle_t queue, size_t global_0,
				psycl_buffer_handle_t input, psycl_buffer_handle_t output,
				size_t N, psycl_buffer_handle_t error);
extern int psycl_f32_to_f16(psycl_queue_handle_t queue, size_t global_0,
				psycl_buffer_handle_t input, psycl_buffer_handle_t output,
				size_t N, psycl_buffer_handle_t error);

int main(void) {
	enum { N = 6 };
	const size_t n = N;
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

	uint16_t in_f16[N] = {
		0x0000u, /* 0.0 */
		0x3C00u, /* 1.0 */
		0x4000u, /* 2.0 */
		0x3800u, /* 0.5 */
		0xBC00u, /* -1.0 */
		0xC000u  /* -2.0 */
	};
	float in_f32[N] = {0.0f, 1.0f, 2.0f, 0.5f, -1.0f, -2.0f};
	float out_f32[N] = {0};
	uint16_t out_f16[N] = {0};

	psycl_buffer_handle_t buf_in_f16 = NULL;
	psycl_buffer_handle_t buf_out_f32 = NULL;
	psycl_buffer_handle_t buf_in_f32 = NULL;
	psycl_buffer_handle_t buf_out_f16 = NULL;

	status = psycl_buffer_create_f16(&buf_in_f16, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_out_f32, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_in_f32, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f16(&buf_out_f16, n);
	PSYCL_TEST_CHECK(status);



	status = psycl_buffer_write_f16(buf_in_f16, in_f16, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_write_f32(buf_in_f32, in_f32, n);
	PSYCL_TEST_CHECK(status);



	status = psycl_f16_to_f32(queue, n, buf_in_f16, buf_out_f32, n, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_f32(buf_out_f32, out_f32, n);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t i = 0; i < n; i++) {
		if (fabsf(out_f32[i] - in_f32[i]) > 1e-3f) {
			correct = false;
			break;
		}
	}

	if (!correct) {
		goto cleanup;
	}


	status = psycl_f32_to_f16(queue, n, buf_in_f32, buf_out_f16, n, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_f16(buf_out_f16, out_f16, n);
	PSYCL_TEST_CHECK(status);

	for (size_t i = 0; i < n; i++) {
		if (out_f16[i] != in_f16[i]) {
			correct = false;
			break;
		}
	}

	if (!correct) {
		goto cleanup;
	}

	/* Round-trip: f32 -> f16 -> f32 */
	status = psycl_f16_to_f32(queue, n, buf_out_f16, buf_out_f32, n, NULL);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_f32(buf_out_f32, out_f32, n);
	PSYCL_TEST_CHECK(status);

	for (size_t i = 0; i < n; i++) {
		if (fabsf(out_f32[i] - in_f32[i]) > 1e-3f) {
			correct = false;
			break;
		}
	}

cleanup:
	if (buf_in_f16) psycl_buffer_destroy_f16(buf_in_f16);
	if (buf_out_f32) psycl_buffer_destroy_f32(buf_out_f32);
	if (buf_in_f32) psycl_buffer_destroy_f32(buf_in_f32);
	if (buf_out_f16) psycl_buffer_destroy_f16(buf_out_f16);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
