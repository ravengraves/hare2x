/* Test harness for test_u32_debug.pka - Pure C11 */
#include "pika_sycl_runtime.h"
#include "psycl_test.h"
#include "test_u32_debug.hpp"
#include <stdbool.h>
#include <stdint.h>

int main(void) {
    bool ok = false;
    int status = PSYCL_SUCCESS;

    status = psycl_runtime_init();
	if (status != PSYCL_SUCCESS) return 1;

    psycl_queue_handle_t queue = psycl_get_default_queue();
    if (!queue) { psycl_runtime_fini(); return 1; }



    status = psycl_test(queue, 1, NULL);
    PSYCL_TEST_CHECK(status);

    status = psycl_queue_wait(queue);
    PSYCL_TEST_CHECK(status);

    ok = true;

cleanup:
    psycl_runtime_fini();


    return ok ? 0 : 1;
}
