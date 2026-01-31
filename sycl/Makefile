# SYCL Test Harness Makefile

.PHONY: all clean check help

# Detect SYCL compilers
ICPX := $(shell command -v icpx 2>/dev/null)
ACPP := $(shell command -v acpp 2>/dev/null)

# Determine which compiler to use
ifdef ICPX
    SYCL_CXX := icpx
    SYCL_FLAGS := -fsycl
    SYCL_IMPL := DPC++
else ifdef ACPP
    SYCL_CXX := acpp
    SYCL_FLAGS := --acpp-targets="omp"
    SYCL_IMPL := AdaptiveCpp
else
    SYCL_CXX :=
    SYCL_IMPL := none
endif

# Compiler flags
CXXFLAGS := -std=c++17 -Wall -Wextra -O2 -I.

# Targets
TARGET := sycl_test_runner
RUNTIME_OBJ := pika_sycl_runtime.o

all:
	@if [ "$(SYCL_IMPL)" = "none" ]; then \
		echo "No SYCL compiler detected. Skipping build."; \
		echo "Install Intel DPC++ (icpx) or AdaptiveCpp (acpp)."; \
		exit 0; \
	fi
	@echo "Building SYCL runtime and test harness with $(SYCL_IMPL)..."
	$(MAKE) $(RUNTIME_OBJ)
	$(MAKE) $(TARGET)

$(RUNTIME_OBJ): pika_sycl_runtime.cpp pika_sycl_runtime.h
	$(SYCL_CXX) $(SYCL_FLAGS) $(CXXFLAGS) -c pika_sycl_runtime.cpp -o $(RUNTIME_OBJ)

$(TARGET): test_runner.cpp kernel_output.sycl.hpp $(RUNTIME_OBJ)
	$(SYCL_CXX) $(SYCL_FLAGS) $(CXXFLAGS) test_runner.cpp $(RUNTIME_OBJ) -o $(TARGET)

check: $(TARGET)
	./$(TARGET)

check-%: $(TARGET)
	./$(TARGET) $*

clean:
	rm -f $(TARGET) $(RUNTIME_OBJ) kernel_output.sycl.hpp

help:
	@echo "SYCL Test Harness Makefile"
	@echo ""
	@echo "Detected SYCL implementation: $(SYCL_IMPL)"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build test runner (if SYCL available)"
	@echo "  make check    - Run all tests"
	@echo "  make check-<test> - Run specific test (e.g., make check-vector_add)"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make help     - Show this message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Intel DPC++ (icpx) or AdaptiveCpp (acpp)"
	@echo ""

.DEFAULT_GOAL := help
