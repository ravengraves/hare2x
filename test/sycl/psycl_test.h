#ifndef PSYCL_TEST_H
#define PSYCL_TEST_H

#include <stdio.h>

#define PSYCL_TEST_CHECK(status) do { \
	if ((status) != PSYCL_SUCCESS) { \
		fprintf(stderr, "FAIL: %s (%d)\n", #status, (int)(status)); \
		goto cleanup; \
	} \
} while (0)

#define PSYCL_TEST_CHECK_PTR(ptr) do { \
	if ((ptr) == NULL) { \
		fprintf(stderr, "FAIL: %s\n", #ptr); \
		goto cleanup; \
	} \
} while (0)

#endif
