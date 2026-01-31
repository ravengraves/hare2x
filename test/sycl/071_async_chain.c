/* Test harness for 071_async_chain.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "071_async_chain.hpp"

#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

extern int psycl_add_one_async(psycl_queue_handle_t queue, size_t global_0,
				psycl_buffer_handle_t input, psycl_buffer_handle_t output,
				size_t N, psycl_event_handle_t* out_event, psycl_buffer_handle_t error);
extern int psycl_mul_two_async(psycl_queue_handle_t queue, size_t global_0,
				psycl_buffer_handle_t input, psycl_buffer_handle_t output,
				size_t N, psycl_event_handle_t* out_event, psycl_buffer_handle_t error);

int main(void) {
	const size_t N = 1024;
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
	psycl_buffer_handle_t buf_tmp = NULL;
	psycl_buffer_handle_t buf_out = NULL;
	psycl_event_handle_t events[5] = { 0 };
	size_t event_count = 0;

	if (!input || !output) {
		goto cleanup;
	}

	status = psycl_buffer_create_f32(&buf_in, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_tmp, N);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_f32(&buf_out, N);
	PSYCL_TEST_CHECK(status);


	for (size_t i = 0; i < N; i++) {
		input[i] = (float)i;
		output[i] = 0.0f;
	}

	status = psycl_buffer_write_async_f32(queue, buf_in, input, N,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_buffer_write_async_f32(queue, buf_out, output, N,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_add_one_async(queue, N, buf_in, buf_tmp, N,
		&events[event_count], NULL);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_mul_two_async(queue, N, buf_tmp, buf_out, N,
		&events[event_count], NULL);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_buffer_read_async_f32(queue, buf_out, output, N,
		&events[event_count]);
	PSYCL_TEST_CHECK(status);
	event_count += 1;

	status = psycl_event_wait_all(events, event_count);
	PSYCL_TEST_CHECK(status);

	correct = true;
	for (size_t i = 0; i < N; i++) {
		float expected = (input[i] + 1.0f) * 2.0f;
		if (fabsf(output[i] - expected) > 1e-5f) {
			correct = false;
			break;
		}
	}

cleanup:
	if (event_count > 0) psycl_event_destroy_all(events, event_count);
	if (buf_in) psycl_buffer_destroy_f32(buf_in);
	if (buf_tmp) psycl_buffer_destroy_f32(buf_tmp);
	if (buf_out) psycl_buffer_destroy_f32(buf_out);
	free(input);
	free(output);
	psycl_runtime_fini();


	return correct ? 0 : 1;
}
