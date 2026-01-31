/* Test harness for 077_string_literals.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "077_string_literals.hpp"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
	const size_t bytes_len = 10;
	const size_t meta_len = 5;
	int status = PSYCL_SUCCESS;
	bool ok = true;

	uint8_t out_bytes[10] = {0};
	uint32_t out_meta[5] = {0};

	psycl_buffer_handle_t buf_bytes = NULL;
	psycl_buffer_handle_t buf_meta = NULL;
	psycl_buffer_handle_t error = NULL;

	status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

	psycl_queue_handle_t queue = psycl_get_default_queue();
	if (!queue) { psycl_runtime_fini(); return 1; }

	status = psycl_buffer_create_u8(&buf_bytes, bytes_len);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_create_u32(&buf_meta, meta_len);
	PSYCL_TEST_CHECK(status);
	status = psycl_error_buffer_create(&error);
	PSYCL_TEST_CHECK(status);
	status = psycl_error_buffer_reset(error);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_write_u8(buf_bytes, out_bytes, bytes_len);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_write_u32(buf_meta, out_meta, meta_len);
	PSYCL_TEST_CHECK(status);

	status = psycl_string_literals(queue, 1, buf_bytes, buf_meta, error);
	PSYCL_TEST_CHECK(status);

	status = psycl_queue_wait(queue);
	PSYCL_TEST_CHECK(status);

	status = psycl_buffer_read_u8(buf_bytes, out_bytes, bytes_len);
	PSYCL_TEST_CHECK(status);
	status = psycl_buffer_read_u32(buf_meta, out_meta, meta_len);
	PSYCL_TEST_CHECK(status);

	psycl_error_t err = psycl_error_buffer_fetch(error);
	if (!psycl_error_is_ok(err)) {
		ok = false;
		goto cleanup;
	}

	const uint8_t expected_bytes[10] = {
		(uint8_t)'A', (uint8_t)'\n', (uint8_t)'B', (uint8_t)'\t', (uint8_t)'C',
		(uint8_t)'r', (uint8_t)'a', (uint8_t)'w', (uint8_t)'\\', (uint8_t)'n',
	};
	const uint32_t expected_meta[5] = {
		5u, 5u, (uint32_t)'A', (uint32_t)'\n', (uint32_t)'B',
	};

	if (memcmp(out_bytes, expected_bytes, bytes_len) != 0) ok = false;
	if (memcmp(out_meta, expected_meta, sizeof(expected_meta)) != 0) ok = false;

cleanup:
	if (error) psycl_error_buffer_destroy(error);
	if (buf_bytes) psycl_buffer_destroy_u8(buf_bytes);
	if (buf_meta) psycl_buffer_destroy_u32(buf_meta);
	psycl_runtime_fini();

	return ok ? 0 : 1;
}
