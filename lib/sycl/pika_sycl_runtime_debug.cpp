// pika_sycl_runtime_debug.cpp - SYCL C API Runtime with Debug Output
// Compile with: icpx -fsycl -c pika_sycl_runtime_debug.cpp

#include "pika_sycl_runtime.h"
#include <sycl/sycl.hpp>
#include <cstdint>
#include <cstring>
#include <iostream>

struct f16 {
	uint16_t bits;
};

// ============================================================================
// Global State
// ============================================================================

static sycl::queue* g_default_queue = nullptr;

// ============================================================================
// Runtime Initialization
// ============================================================================

int psycl_runtime_init(void) {
	if (g_default_queue) {
		std::cout << "[DEBUG] Runtime already initialized\n";
		return PSYCL_SUCCESS;
	}

	try {
		std::cout << "[DEBUG] Creating default queue...\n";
		g_default_queue = new sycl::queue();

		auto device = g_default_queue->get_device();
		auto platform = device.get_platform();

		std::cout << "[DEBUG] Queue created successfully\n";
		std::cout << "[DEBUG] Platform: " << platform.get_info<sycl::info::platform::name>() << "\n";
		std::cout << "[DEBUG] Device: " << device.get_info<sycl::info::device::name>() << "\n";
		std::cout << "[DEBUG] Device type: ";

		if (device.is_cpu()) std::cout << "CPU\n";
		else if (device.is_gpu()) std::cout << "GPU\n";
		else if (device.is_accelerator()) std::cout << "Accelerator\n";
		else std::cout << "Unknown\n";

		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in init: " << e.what() << "\n";
		return PSYCL_ERROR_QUEUE_INIT;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in init: " << e.what() << "\n";
		return PSYCL_ERROR_QUEUE_INIT;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in init\n";
		return PSYCL_ERROR_QUEUE_INIT;
	}
}

void psycl_runtime_fini(void) {
	std::cout << "[DEBUG] Finalizing runtime...\n";
	if (g_default_queue) {
		delete g_default_queue;
		g_default_queue = nullptr;
		std::cout << "[DEBUG] Runtime finalized\n";
	}
}

psycl_queue_handle_t psycl_get_default_queue(void) {
	std::cout << "[DEBUG] Getting default queue: " << (void*)g_default_queue << "\n";
	return reinterpret_cast<psycl_queue_handle_t>(g_default_queue);
}

// ============================================================================
// Queue Management
// ============================================================================

int psycl_create_queue(psycl_queue_handle_t* handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Creating new queue...\n";
		auto* q = new sycl::queue();
		*handle = reinterpret_cast<psycl_queue_handle_t>(q);
		std::cout << "[DEBUG] Queue created: " << (void*)q << "\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in create_queue: " << e.what() << "\n";
		return PSYCL_ERROR_QUEUE_INIT;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in create_queue\n";
		return PSYCL_ERROR_QUEUE_INIT;
	}
}

int psycl_destroy_queue(psycl_queue_handle_t handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	std::cout << "[DEBUG] Destroying queue: " << handle << "\n";
	auto* q = reinterpret_cast<sycl::queue*>(handle);
	delete q;
	return PSYCL_SUCCESS;
}

int psycl_queue_wait(psycl_queue_handle_t handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Waiting on queue: " << handle << "\n";
		auto* q = reinterpret_cast<sycl::queue*>(handle);
		q->wait();
		std::cout << "[DEBUG] Queue wait completed\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in queue_wait: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in queue_wait: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in queue_wait\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

// ============================================================================
// Event Management
// ============================================================================

int psycl_event_wait(psycl_event_handle_t handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Waiting on event: " << handle << "\n";
		auto* evt = reinterpret_cast<sycl::event*>(handle);
		evt->wait();
		std::cout << "[DEBUG] Event wait completed\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in event_wait: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in event_wait: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in event_wait\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

int psycl_event_wait_all(const psycl_event_handle_t* events, size_t count) {
	if (!events && count > 0) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Waiting on " << count << " event(s)\n";
		for (size_t i = 0; i < count; i += 1) {
			if (!events[i]) return PSYCL_ERROR_INVALID_PARAM;
			auto* evt = reinterpret_cast<sycl::event*>(events[i]);
			evt->wait();
		}
		std::cout << "[DEBUG] Event wait_all completed\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in event_wait_all: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in event_wait_all: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in event_wait_all\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

int psycl_event_destroy_all(const psycl_event_handle_t* events, size_t count) {
	if (!events && count > 0) return PSYCL_ERROR_INVALID_PARAM;
	std::cout << "[DEBUG] Destroying " << count << " event(s)\n";
	for (size_t i = 0; i < count; i += 1) {
		if (!events[i]) return PSYCL_ERROR_INVALID_PARAM;
		auto* evt = reinterpret_cast<sycl::event*>(events[i]);
		delete evt;
	}
	std::cout << "[DEBUG] Event destroy_all completed\n";
	return PSYCL_SUCCESS;
}

int psycl_event_destroy(psycl_event_handle_t handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	std::cout << "[DEBUG] Destroying event: " << handle << "\n";
	auto* evt = reinterpret_cast<sycl::event*>(handle);
	delete evt;
	return PSYCL_SUCCESS;
}

// ============================================================================
// Buffer Management (portable across backends)
// ============================================================================

namespace {

template <typename T>
static int buffer_create_impl(psycl_buffer_handle_t* out, size_t count) {
	if (!out) return PSYCL_ERROR_INVALID_PARAM;
	try {
		auto* buf = new sycl::buffer<T, 1>(sycl::range<1>(count));
		*out = reinterpret_cast<psycl_buffer_handle_t>(buf);
		std::cout << "[DEBUG] Created buffer (" << count << " elements)\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in buffer_create: " << e.what() << "\n";
		return PSYCL_ERROR_MEMORY_ALLOC;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in buffer_create: " << e.what() << "\n";
		return PSYCL_ERROR_MEMORY_ALLOC;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in buffer_create\n";
		return PSYCL_ERROR_MEMORY_ALLOC;
	}
}

template <typename T>
static int buffer_destroy_impl(psycl_buffer_handle_t handle) {
	if (!handle) return PSYCL_ERROR_INVALID_PARAM;
	auto* buf = reinterpret_cast<sycl::buffer<T, 1>*>(handle);
	delete buf;
	std::cout << "[DEBUG] Destroyed buffer\n";
	return PSYCL_SUCCESS;
}

template <typename T>
static int buffer_write_impl(psycl_buffer_handle_t handle, const void* src, size_t count) {
	if (!handle || (!src && count > 0)) return PSYCL_ERROR_INVALID_PARAM;
	auto* buf = reinterpret_cast<sycl::buffer<T, 1>*>(handle);
	size_t buf_count = buf->get_range().size();
	if (count > buf_count) return PSYCL_ERROR_INVALID_PARAM;
	try {
		sycl::host_accessor<T, 1, sycl::access::mode::write> acc(*buf);
		if (count > 0) {
			std::memcpy(&acc[0], src, count * sizeof(T));
		}
		std::cout << "[DEBUG] Wrote " << count << " elements to buffer\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in buffer_write: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in buffer_write: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in buffer_write\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

template <typename T>
static int buffer_read_impl(psycl_buffer_handle_t handle, void* dst, size_t count) {
	if (!handle || (!dst && count > 0)) return PSYCL_ERROR_INVALID_PARAM;
	auto* buf = reinterpret_cast<sycl::buffer<T, 1>*>(handle);
	size_t buf_count = buf->get_range().size();
	if (count > buf_count) return PSYCL_ERROR_INVALID_PARAM;
	try {
		sycl::host_accessor<T, 1, sycl::access::mode::read> acc(*buf);
		if (count > 0) {
			std::memcpy(dst, &acc[0], count * sizeof(T));
		}
		std::cout << "[DEBUG] Read " << count << " elements from buffer\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in buffer_read: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in buffer_read: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in buffer_read\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

template <typename T>
static int buffer_write_async_impl(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                  const void* src, size_t count, psycl_event_handle_t* out_event) {
	if (!queue || !handle || (!src && count > 0) || !out_event) return PSYCL_ERROR_INVALID_PARAM;
	auto* q = reinterpret_cast<sycl::queue*>(queue);
	auto* buf = reinterpret_cast<sycl::buffer<T, 1>*>(handle);
	size_t buf_count = buf->get_range().size();
	if (count > buf_count) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Submitting async buffer write (" << count << " elements)\n";
		auto evt = q->submit([&](sycl::handler& h) {
			auto acc = buf->template get_access<sycl::access::mode::write>(h);
			h.copy(static_cast<const T*>(src), acc);
		});
		*out_event = reinterpret_cast<psycl_event_handle_t>(new sycl::event(evt));
		std::cout << "[DEBUG] Async buffer write submitted\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in buffer_write_async: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in buffer_write_async: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in buffer_write_async\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

template <typename T>
static int buffer_read_async_impl(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                                 void* dst, size_t count, psycl_event_handle_t* out_event) {
	if (!queue || !handle || (!dst && count > 0) || !out_event) return PSYCL_ERROR_INVALID_PARAM;
	auto* q = reinterpret_cast<sycl::queue*>(queue);
	auto* buf = reinterpret_cast<sycl::buffer<T, 1>*>(handle);
	size_t buf_count = buf->get_range().size();
	if (count > buf_count) return PSYCL_ERROR_INVALID_PARAM;
	try {
		std::cout << "[DEBUG] Submitting async buffer read (" << count << " elements)\n";
		auto evt = q->submit([&](sycl::handler& h) {
			auto acc = buf->template get_access<sycl::access::mode::read>(h);
			h.copy(acc, static_cast<T*>(dst));
		});
		*out_event = reinterpret_cast<psycl_event_handle_t>(new sycl::event(evt));
		std::cout << "[DEBUG] Async buffer read submitted\n";
		return PSYCL_SUCCESS;
	} catch (const sycl::exception& e) {
		std::cerr << "[ERROR] SYCL exception in buffer_read_async: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (const std::exception& e) {
		std::cerr << "[ERROR] Exception in buffer_read_async: " << e.what() << "\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	} catch (...) {
		std::cerr << "[ERROR] Unknown exception in buffer_read_async\n";
		return PSYCL_ERROR_KERNEL_LAUNCH;
	}
}

}  // namespace

int psycl_buffer_create(psycl_buffer_handle_t* out, psycl_buffer_type_t type, size_t count) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_create_impl<float>(out, count);
	case PSYCL_BUFFER_F64: return buffer_create_impl<double>(out, count);
	case PSYCL_BUFFER_F16: return buffer_create_impl<f16>(out, count);
	case PSYCL_BUFFER_I8: return buffer_create_impl<int8_t>(out, count);
	case PSYCL_BUFFER_U8: return buffer_create_impl<uint8_t>(out, count);
	case PSYCL_BUFFER_I16: return buffer_create_impl<int16_t>(out, count);
	case PSYCL_BUFFER_U16: return buffer_create_impl<uint16_t>(out, count);
	case PSYCL_BUFFER_I32: return buffer_create_impl<int32_t>(out, count);
	case PSYCL_BUFFER_U32: return buffer_create_impl<uint32_t>(out, count);
	case PSYCL_BUFFER_I64: return buffer_create_impl<int64_t>(out, count);
	case PSYCL_BUFFER_U64: return buffer_create_impl<uint64_t>(out, count);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}

int psycl_buffer_destroy(psycl_buffer_handle_t handle, psycl_buffer_type_t type) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_destroy_impl<float>(handle);
	case PSYCL_BUFFER_F64: return buffer_destroy_impl<double>(handle);
	case PSYCL_BUFFER_F16: return buffer_destroy_impl<f16>(handle);
	case PSYCL_BUFFER_I8: return buffer_destroy_impl<int8_t>(handle);
	case PSYCL_BUFFER_U8: return buffer_destroy_impl<uint8_t>(handle);
	case PSYCL_BUFFER_I16: return buffer_destroy_impl<int16_t>(handle);
	case PSYCL_BUFFER_U16: return buffer_destroy_impl<uint16_t>(handle);
	case PSYCL_BUFFER_I32: return buffer_destroy_impl<int32_t>(handle);
	case PSYCL_BUFFER_U32: return buffer_destroy_impl<uint32_t>(handle);
	case PSYCL_BUFFER_I64: return buffer_destroy_impl<int64_t>(handle);
	case PSYCL_BUFFER_U64: return buffer_destroy_impl<uint64_t>(handle);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}

int psycl_buffer_write(psycl_buffer_handle_t handle, psycl_buffer_type_t type,
                      const void* src, size_t count) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_write_impl<float>(handle, src, count);
	case PSYCL_BUFFER_F64: return buffer_write_impl<double>(handle, src, count);
	case PSYCL_BUFFER_F16: return buffer_write_impl<f16>(handle, src, count);
	case PSYCL_BUFFER_I8: return buffer_write_impl<int8_t>(handle, src, count);
	case PSYCL_BUFFER_U8: return buffer_write_impl<uint8_t>(handle, src, count);
	case PSYCL_BUFFER_I16: return buffer_write_impl<int16_t>(handle, src, count);
	case PSYCL_BUFFER_U16: return buffer_write_impl<uint16_t>(handle, src, count);
	case PSYCL_BUFFER_I32: return buffer_write_impl<int32_t>(handle, src, count);
	case PSYCL_BUFFER_U32: return buffer_write_impl<uint32_t>(handle, src, count);
	case PSYCL_BUFFER_I64: return buffer_write_impl<int64_t>(handle, src, count);
	case PSYCL_BUFFER_U64: return buffer_write_impl<uint64_t>(handle, src, count);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}

int psycl_buffer_read(psycl_buffer_handle_t handle, psycl_buffer_type_t type,
                     void* dst, size_t count) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_read_impl<float>(handle, dst, count);
	case PSYCL_BUFFER_F64: return buffer_read_impl<double>(handle, dst, count);
	case PSYCL_BUFFER_F16: return buffer_read_impl<f16>(handle, dst, count);
	case PSYCL_BUFFER_I8: return buffer_read_impl<int8_t>(handle, dst, count);
	case PSYCL_BUFFER_U8: return buffer_read_impl<uint8_t>(handle, dst, count);
	case PSYCL_BUFFER_I16: return buffer_read_impl<int16_t>(handle, dst, count);
	case PSYCL_BUFFER_U16: return buffer_read_impl<uint16_t>(handle, dst, count);
	case PSYCL_BUFFER_I32: return buffer_read_impl<int32_t>(handle, dst, count);
	case PSYCL_BUFFER_U32: return buffer_read_impl<uint32_t>(handle, dst, count);
	case PSYCL_BUFFER_I64: return buffer_read_impl<int64_t>(handle, dst, count);
	case PSYCL_BUFFER_U64: return buffer_read_impl<uint64_t>(handle, dst, count);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}

int psycl_buffer_write_async(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                            psycl_buffer_type_t type, const void* src, size_t count,
                            psycl_event_handle_t* out_event) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_write_async_impl<float>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_F64: return buffer_write_async_impl<double>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_F16: return buffer_write_async_impl<f16>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_I8: return buffer_write_async_impl<int8_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_U8: return buffer_write_async_impl<uint8_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_I16: return buffer_write_async_impl<int16_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_U16: return buffer_write_async_impl<uint16_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_I32: return buffer_write_async_impl<int32_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_U32: return buffer_write_async_impl<uint32_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_I64: return buffer_write_async_impl<int64_t>(queue, handle, src, count, out_event);
	case PSYCL_BUFFER_U64: return buffer_write_async_impl<uint64_t>(queue, handle, src, count, out_event);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}

int psycl_buffer_read_async(psycl_queue_handle_t queue, psycl_buffer_handle_t handle,
                           psycl_buffer_type_t type, void* dst, size_t count,
                           psycl_event_handle_t* out_event) {
	switch (type) {
	case PSYCL_BUFFER_F32: return buffer_read_async_impl<float>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_F64: return buffer_read_async_impl<double>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_F16: return buffer_read_async_impl<f16>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_I8: return buffer_read_async_impl<int8_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_U8: return buffer_read_async_impl<uint8_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_I16: return buffer_read_async_impl<int16_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_U16: return buffer_read_async_impl<uint16_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_I32: return buffer_read_async_impl<int32_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_U32: return buffer_read_async_impl<uint32_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_I64: return buffer_read_async_impl<int64_t>(queue, handle, dst, count, out_event);
	case PSYCL_BUFFER_U64: return buffer_read_async_impl<uint64_t>(queue, handle, dst, count, out_event);
	default: return PSYCL_ERROR_INVALID_PARAM;
	}
}
