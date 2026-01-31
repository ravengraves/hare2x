// pika_sycl_runtime.h - SYCL C API Runtime
//
// This file provides a C API for SYCL operations (queue management,
// memory allocation) that can be linked with generated kernel code.
//
// Link with: pika_sycl_runtime.cpp
// Compile with: icpx -fsycl or acpp --acpp-targets=...

#ifndef PIKA_SYCL_RUNTIME_H
#define PIKA_SYCL_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Status Codes
// ============================================================================

#define PSYCL_SUCCESS 0
#define PSYCL_ERROR_QUEUE_INIT -1
#define PSYCL_ERROR_KERNEL_LAUNCH -2
#define PSYCL_ERROR_MEMORY_ALLOC -3
#define PSYCL_ERROR_INVALID_PARAM -4

// ============================================================================
// Opaque Queue Handle
// ============================================================================

typedef void* psycl_queue_handle_t;

// Opaque event handle
typedef void* psycl_event_handle_t;

// ============================================================================
// Opaque Buffer Handle + Types
// ============================================================================

typedef void* psycl_buffer_handle_t;

typedef enum psycl_buffer_type_t {
	PSYCL_BUFFER_F32 = 1,
	PSYCL_BUFFER_F64 = 2,
	PSYCL_BUFFER_I8 = 3,
	PSYCL_BUFFER_U8 = 4,
	PSYCL_BUFFER_I16 = 5,
	PSYCL_BUFFER_U16 = 6,
	PSYCL_BUFFER_I32 = 7,
	PSYCL_BUFFER_U32 = 8,
	PSYCL_BUFFER_I64 = 9,
	PSYCL_BUFFER_U64 = 10,
	PSYCL_BUFFER_F16 = 11
} psycl_buffer_type_t;

// ============================================================================
// Kernel Error Reporting
// ============================================================================

typedef struct psycl_error_t {
	uint32_t code;
	uint32_t loc;
} psycl_error_t;

// 0 = success; 3 = kernel launch or runtime failure
#define PSYCL_ERROR_CODE_KERNEL_LAUNCH 3u

static inline psycl_error_t psycl_error_none(void) {
	psycl_error_t err = {0u, 0u};
	return err;
}

static inline psycl_error_t psycl_error_kernel_launch(void) {
	psycl_error_t err = {PSYCL_ERROR_CODE_KERNEL_LAUNCH, 0u};
	return err;
}

static inline int psycl_error_is_ok(psycl_error_t err) {
	return err.code == 0u;
}

static inline psycl_error_t psycl_error_from_words(const uint32_t words[2]) {
	psycl_error_t err = {words[0], words[1]};
	return err;
}

// ============================================================================
// Runtime Initialization
// ============================================================================

// Initialize SYCL runtime (creates default queue)
// Call once at program startup
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_QUEUE_INIT
int psycl_runtime_init(void);

// Cleanup SYCL runtime (destroys default queue)
// Call once at program shutdown
void psycl_runtime_fini(void);

// Get the default queue (created by psycl_runtime_init)
// Returns: Queue handle or NULL if runtime not initialized
psycl_queue_handle_t psycl_get_default_queue(void);

// ============================================================================
// Queue Management
// ============================================================================

// Create a SYCL queue (default device selector)
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_QUEUE_INIT
int psycl_create_queue(psycl_queue_handle_t* handle);

// Destroy a SYCL queue
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_destroy_queue(psycl_queue_handle_t handle);

// Wait for all queue operations to complete
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_KERNEL_LAUNCH
int psycl_queue_wait(psycl_queue_handle_t handle);

// ============================================================================
// Event Management
// ============================================================================

// Wait for an event to complete
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_KERNEL_LAUNCH
int psycl_event_wait(psycl_event_handle_t handle);

// Wait for all events to complete
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM / PSYCL_ERROR_KERNEL_LAUNCH
int psycl_event_wait_all(const psycl_event_handle_t* events, size_t count);

// Destroy a list of event handles
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_event_destroy_all(const psycl_event_handle_t* events, size_t count);

// Destroy an event handle
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_event_destroy(psycl_event_handle_t handle);

// ============================================================================
// Buffer Management (portable across backends)
// ============================================================================

// Create a typed SYCL buffer with element count
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_MEMORY_ALLOC
int psycl_buffer_create(psycl_buffer_handle_t* out, psycl_buffer_type_t type, size_t count);

// Destroy a typed SYCL buffer
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_buffer_destroy(psycl_buffer_handle_t handle, psycl_buffer_type_t type);

// Copy from host to buffer (count elements)
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_buffer_write(psycl_buffer_handle_t handle, psycl_buffer_type_t type,
                      const void* src, size_t count);

// Copy from buffer to host (count elements)
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM
int psycl_buffer_read(psycl_buffer_handle_t handle, psycl_buffer_type_t type,
                     void* dst, size_t count);

// Async copy from host to buffer (count elements)
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM / PSYCL_ERROR_KERNEL_LAUNCH
int psycl_buffer_write_async(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                            psycl_buffer_type_t type, const void* src, size_t count,
                            psycl_event_handle_t* out_event);

// Async copy from buffer to host (count elements)
// Returns: PSYCL_SUCCESS or PSYCL_ERROR_INVALID_PARAM / PSYCL_ERROR_KERNEL_LAUNCH
int psycl_buffer_read_async(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                           psycl_buffer_type_t type, void* dst, size_t count,
                           psycl_event_handle_t* out_event);

// ============================================================================
// Typed Convenience Helpers
// ============================================================================

static inline int psycl_buffer_create_f32(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_F32, count);
}
static inline int psycl_buffer_destroy_f32(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_F32);
}
static inline int psycl_buffer_write_f32(psycl_buffer_handle_t handle, const float* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_F32, src, count);
}
static inline int psycl_buffer_read_f32(psycl_buffer_handle_t handle, float* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_F32, dst, count);
}
static inline int psycl_buffer_write_async_f32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const float* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_F32, src, count, out_event);
}
static inline int psycl_buffer_read_async_f32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             float* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_F32, dst, count, out_event);
}

static inline int psycl_buffer_create_f64(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_F64, count);
}
static inline int psycl_buffer_destroy_f64(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_F64);
}
static inline int psycl_buffer_write_f64(psycl_buffer_handle_t handle, const double* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_F64, src, count);
}
static inline int psycl_buffer_read_f64(psycl_buffer_handle_t handle, double* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_F64, dst, count);
}
static inline int psycl_buffer_write_async_f64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const double* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_F64, src, count, out_event);
}
static inline int psycl_buffer_read_async_f64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             double* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_F64, dst, count, out_event);
}

static inline int psycl_buffer_create_f16(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_F16, count);
}
static inline int psycl_buffer_destroy_f16(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_F16);
}
static inline int psycl_buffer_write_f16(psycl_buffer_handle_t handle, const uint16_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_F16, src, count);
}
static inline int psycl_buffer_read_f16(psycl_buffer_handle_t handle, uint16_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_F16, dst, count);
}
static inline int psycl_buffer_write_async_f16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const uint16_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_F16, src, count, out_event);
}
static inline int psycl_buffer_read_async_f16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             uint16_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_F16, dst, count, out_event);
}

static inline int psycl_buffer_create_i8(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_I8, count);
}
static inline int psycl_buffer_destroy_i8(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_I8);
}
static inline int psycl_buffer_write_i8(psycl_buffer_handle_t handle, const int8_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_I8, src, count);
}
static inline int psycl_buffer_read_i8(psycl_buffer_handle_t handle, int8_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_I8, dst, count);
}
static inline int psycl_buffer_write_async_i8(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             const int8_t* src, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_I8, src, count, out_event);
}
static inline int psycl_buffer_read_async_i8(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                            int8_t* dst, size_t count,
                                            psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_I8, dst, count, out_event);
}

static inline int psycl_buffer_create_u8(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_U8, count);
}
static inline int psycl_buffer_destroy_u8(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_U8);
}
static inline int psycl_buffer_write_u8(psycl_buffer_handle_t handle, const uint8_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_U8, src, count);
}
static inline int psycl_buffer_read_u8(psycl_buffer_handle_t handle, uint8_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_U8, dst, count);
}
static inline int psycl_buffer_write_async_u8(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             const uint8_t* src, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_U8, src, count, out_event);
}
static inline int psycl_buffer_read_async_u8(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                            uint8_t* dst, size_t count,
                                            psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_U8, dst, count, out_event);
}

static inline int psycl_buffer_create_i16(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_I16, count);
}
static inline int psycl_buffer_destroy_i16(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_I16);
}
static inline int psycl_buffer_write_i16(psycl_buffer_handle_t handle, const int16_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_I16, src, count);
}
static inline int psycl_buffer_read_i16(psycl_buffer_handle_t handle, int16_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_I16, dst, count);
}
static inline int psycl_buffer_write_async_i16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const int16_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_I16, src, count, out_event);
}
static inline int psycl_buffer_read_async_i16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             int16_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_I16, dst, count, out_event);
}

static inline int psycl_buffer_create_u16(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_U16, count);
}
static inline int psycl_buffer_destroy_u16(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_U16);
}
static inline int psycl_buffer_write_u16(psycl_buffer_handle_t handle, const uint16_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_U16, src, count);
}
static inline int psycl_buffer_read_u16(psycl_buffer_handle_t handle, uint16_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_U16, dst, count);
}
static inline int psycl_buffer_write_async_u16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const uint16_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_U16, src, count, out_event);
}
static inline int psycl_buffer_read_async_u16(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             uint16_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_U16, dst, count, out_event);
}

static inline int psycl_buffer_create_i32(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_I32, count);
}
static inline int psycl_buffer_destroy_i32(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_I32);
}
static inline int psycl_buffer_write_i32(psycl_buffer_handle_t handle, const int32_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_I32, src, count);
}
static inline int psycl_buffer_read_i32(psycl_buffer_handle_t handle, int32_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_I32, dst, count);
}
static inline int psycl_buffer_write_async_i32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const int32_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_I32, src, count, out_event);
}
static inline int psycl_buffer_read_async_i32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             int32_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_I32, dst, count, out_event);
}

static inline int psycl_buffer_create_u32(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_U32, count);
}
static inline int psycl_buffer_destroy_u32(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_U32);
}
static inline int psycl_buffer_write_u32(psycl_buffer_handle_t handle, const uint32_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_U32, src, count);
}
static inline int psycl_buffer_read_u32(psycl_buffer_handle_t handle, uint32_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_U32, dst, count);
}
static inline int psycl_buffer_write_async_u32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const uint32_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_U32, src, count, out_event);
}
static inline int psycl_buffer_read_async_u32(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             uint32_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_U32, dst, count, out_event);
}

static inline int psycl_buffer_create_i64(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_I64, count);
}
static inline int psycl_buffer_destroy_i64(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_I64);
}
static inline int psycl_buffer_write_i64(psycl_buffer_handle_t handle, const int64_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_I64, src, count);
}
static inline int psycl_buffer_read_i64(psycl_buffer_handle_t handle, int64_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_I64, dst, count);
}
static inline int psycl_buffer_write_async_i64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const int64_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_I64, src, count, out_event);
}
static inline int psycl_buffer_read_async_i64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             int64_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_I64, dst, count, out_event);
}

static inline int psycl_buffer_create_u64(psycl_buffer_handle_t* out, size_t count) {
	return psycl_buffer_create(out, PSYCL_BUFFER_U64, count);
}
static inline int psycl_buffer_destroy_u64(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy(handle, PSYCL_BUFFER_U64);
}
static inline int psycl_buffer_write_u64(psycl_buffer_handle_t handle, const uint64_t* src, size_t count) {
	return psycl_buffer_write(handle, PSYCL_BUFFER_U64, src, count);
}
static inline int psycl_buffer_read_u64(psycl_buffer_handle_t handle, uint64_t* dst, size_t count) {
	return psycl_buffer_read(handle, PSYCL_BUFFER_U64, dst, count);
}
static inline int psycl_buffer_write_async_u64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                              const uint64_t* src, size_t count,
                                              psycl_event_handle_t* out_event) {
	return psycl_buffer_write_async(queue, handle, PSYCL_BUFFER_U64, src, count, out_event);
}
static inline int psycl_buffer_read_async_u64(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                             uint64_t* dst, size_t count,
                                             psycl_event_handle_t* out_event) {
	return psycl_buffer_read_async(queue, handle, PSYCL_BUFFER_U64, dst, count, out_event);
}

static inline int psycl_error_buffer_create(psycl_buffer_handle_t* out) {
	if (!out) return PSYCL_SUCCESS;
	return psycl_buffer_create_u32(out, 2);
}

static inline int psycl_error_buffer_destroy(psycl_buffer_handle_t handle) {
	return psycl_buffer_destroy_u32(handle);
}

static inline int psycl_error_buffer_reset(psycl_buffer_handle_t handle) {
	if (!handle) return PSYCL_SUCCESS;
	uint32_t zero[2] = {0u, 0u};
	return psycl_buffer_write_u32(handle, zero, 2);
}

static inline int psycl_error_buffer_read(psycl_buffer_handle_t handle, uint32_t out[2]) {
	return psycl_buffer_read_u32(handle, out, 2);
}

static inline psycl_error_t psycl_error_buffer_fetch(psycl_buffer_handle_t handle) {
	uint32_t raw[2] = {0u, 0u};
	if (psycl_error_buffer_read(handle, raw) != PSYCL_SUCCESS) {
		return psycl_error_kernel_launch();
	}
	return psycl_error_from_words(raw);
}


#ifdef __cplusplus
}
#endif

#endif // PIKA_SYCL_RUNTIME_H
