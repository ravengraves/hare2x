/* Comprehensive SYCL smoketest harness (C11) */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "076_smoketest.hpp"

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static const float g_weights[8] = {
	0.25f, 0.5f, 0.75f, 1.0f,
	1.25f, 1.5f, 1.75f, 2.0f,
};

static const float g_bias[4] = { 0.1f, 0.2f, 0.3f, 0.4f };

static float expected_preprocess(const float* input, size_t i, size_t start) {
	float v = input[start + i];
	float local_slice0 = (v + 1.0f) + 2.0f;
	float w = g_weights[2 + (i % 4u)];
	float b = g_bias[i % 4u];
	return (local_slice0 + w) + b;
}

static float expected_tile(float v, size_t gx, size_t gy) {
	float w = g_weights[2 + ((gx + gy) % 4u)];
	return v * w + 1.0f;
}

int main(void) {
	const size_t width = 16;
	const size_t height = 16;
	const size_t n = width * height;
	const size_t start = 4;
	const size_t input_len = n + start;
	const size_t local_x = 8;
	const size_t local_y = 8;
	const size_t local_tile = local_x * local_y;

	int status = PSYCL_SUCCESS;
	bool ok = true;

	float* host_input = NULL;
	float* host_output = NULL;

	psycl_buffer_handle_t buf_input = NULL;
	psycl_buffer_handle_t buf_tmp = NULL;
	psycl_buffer_handle_t buf_out = NULL;
	psycl_buffer_handle_t buf_check = NULL;
	psycl_buffer_handle_t error = NULL;

	psycl_event_handle_t events[16] = { 0 };
	size_t event_count = 0;

	status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) {
		return 1;
	}

	psycl_queue_handle_t queue = psycl_get_default_queue();
	if (!queue) {
		psycl_runtime_fini();
		return 1;
	}

	host_input = (float*)malloc(input_len * sizeof(float));
	host_output = (float*)malloc(n * sizeof(float));
	if (!host_input || !host_output) {
		goto cleanup;
	}

	for (size_t i = 0; i < input_len; i++) {
		host_input[i] = (float)i * 0.25f;
	}

	status = psycl_buffer_create_f32(&buf_input, input_len);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_tmp, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_out, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_check, n);
	PSYCL_TEST_CHECK(status);
	status = psycl_error_buffer_create(&error);
	PSYCL_TEST_CHECK(status);
	status = psycl_error_buffer_reset(error);
	PSYCL_TEST_CHECK(status);

	// Kernel pipeline: preprocess -> tile2d -> check (async)
	event_count = 0;
	status = psycl_buffer_write_async_f32(queue, buf_input, host_input, input_len,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_smoke_preprocess_async(queue, n,
		buf_input, buf_tmp, n, start, &events[event_count], error);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_smoke_tile2d_async(queue,
		width, height, local_x, local_y, local_tile,
		buf_tmp, buf_out, width, height,
		&events[event_count], error);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_smoke_check_async(queue, n,
		buf_out, buf_check, n, false, &events[event_count], error);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_buffer_read_async_f32(queue, buf_check, host_output, n,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_event_wait_all(events, event_count);
	PSYCL_TEST_CHECK(status);
	status = psycl_event_destroy_all(events, event_count);
	PSYCL_TEST_CHECK(status);
	event_count = 0;

	psycl_error_t err = psycl_error_buffer_fetch(error);
	if (!psycl_error_is_ok(err)) {
		fprintf(stderr, "Unexpected kernel error: code=%u loc=%u\n", err.code, err.loc);
		ok = false;
		goto cleanup;
	}

	for (size_t i = 0; i < n; i++) {
		size_t gx = i % width;
		size_t gy = i / width;
		float tmp = expected_preprocess(host_input, i, start);
		float expected = expected_tile(tmp, gx, gy);
		if (fabsf(host_output[i] - expected) > 1e-4f) {
			ok = false;
			break;
		}
	}

	// Abort path: expect an error
	status = psycl_error_buffer_reset(error);
	PSYCL_TEST_CHECK(status);
	host_input[start + 1] = -1.0f;

	event_count = 0;
	status = psycl_buffer_write_async_f32(queue, buf_input, host_input, input_len,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_smoke_check_async(queue, 4,
		buf_input, buf_tmp, 4, true, &events[event_count], error);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_event_wait_all(events, event_count);
	PSYCL_TEST_CHECK(status);
	status = psycl_event_destroy_all(events, event_count);
	PSYCL_TEST_CHECK(status);
	event_count = 0;

	err = psycl_error_buffer_fetch(error);
	if (psycl_error_is_ok(err)) {
		fprintf(stderr, "Expected abort/assert error, got success\n");
		ok = false;
	}

cleanup:
	if (event_count > 0) {
		psycl_event_destroy_all(events, event_count);
	}
	if (error) {
		psycl_error_buffer_destroy(error);
	}
	if (buf_input) {
		psycl_buffer_destroy_f32(buf_input);
	}
	if (buf_tmp) {
		psycl_buffer_destroy_f32(buf_tmp);
	}
	if (buf_out) {
		psycl_buffer_destroy_f32(buf_out);
	}
	if (buf_check) {
		psycl_buffer_destroy_f32(buf_check);
	}
	free(host_input);
	free(host_output);
	psycl_runtime_fini();

	return ok ? 0 : 1;
}
