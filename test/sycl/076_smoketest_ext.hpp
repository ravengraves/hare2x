#pragma once

#include <sycl/sycl.hpp>

static inline float smoketest_ext_fma(float a, float b, float c) {
	return sycl::fma(a, b, c);
}
