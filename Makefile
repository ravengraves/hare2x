.POSIX:
.PHONY: all clean check hare2c pika2c wasm help install uninstall optimize optimize-hare2c optimize-pika2c check-glsl check-sycl check-module

# Compiler settings
CC = gcc
# Base flags (no strip for BOLT compatibility)
CFLAGS_BASE = -std=c11 -Wall -Wextra -O3 -flto -march=native -mtune=native -ffast-math \
	-Wconversion -Wfloat-conversion -Wno-gnu-auto-type -Wno-unused-function \
	-Wno-gnu-statement-expression -Wno-parentheses-equality -ffunction-sections \
	-fdata-sections -Wl,--gc-sections -ffreestanding -nostdlib -fno-builtin
# Default flags include strip
CFLAGS = $(CFLAGS_BASE) -s
# BOLT flags: no strip, need relocations preserved
CFLAGS_BOLT = $(CFLAGS_BASE) -Wl,--emit-relocs
PYTHON = python3
NODE = $(shell command -v node 2>/dev/null)

# BOLT settings
PERF = perf
PERF2BOLT = perf2bolt
LLVM_BOLT = llvm-bolt
BOLT_OPTS = -reorder-blocks=ext-tsp -reorder-functions=hfsort+ -split-functions \
	-split-all-cold -split-eh -dyno-stats
PROFILE_ITERATIONS = 20

# Directories
BUILD_DIR = build
CMD_DIR = cmd
LIB_DIR = lib
TEST_DIR = test
WASM_DIR = wasm

PREFIX ?= /usr/local

# Outputs
HARE2C = $(BUILD_DIR)/hare2c
PIKA2C = $(BUILD_DIR)/pika2c

# Default target
all: hare2c pika2c

help:
	@echo "Hare2C Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build both transpilers (default)"
	@echo "  make all          - Build both transpilers"
	@echo "  make hare2c       - Build self-hosted Hare transpiler"
	@echo "  make pika2c       - Build self-hosted Pika transpiler"
	@echo "  make optimize     - BOLT-optimize both transpilers"
	@echo "  make optimize-hare2c - BOLT-optimize hare2c"
	@echo "  make optimize-pika2c - BOLT-optimize pika2c"
	@echo "  make check        - Run all test suites"
	@echo "  make check-sycl   - Run SYCL tests (Intel + CUDA if available)"
	@echo "  make check-glsl   - Run GLSL backend tests"
	@echo "  make wasm         - Build both WASM versions"
	@echo "  make install      - install to PREFIX/bin"
	@echo "  make uninstall    - Remove from PREFIX/bin"
	@echo "  make clean        - Remove build artifacts"
	@echo ""
	@echo "BOLT optimization uses perf profiling for better code layout."
	@echo "Requires: perf, perf2bolt, llvm-bolt, strip"
	@echo ""

# Ensure build directory exists
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build self-hosted Hare transpiler
hare2c: $(HARE2C)

$(HARE2C): $(BUILD_DIR)
	@echo "Building hare2c transpiler..."
	$(PYTHON) $(CMD_DIR)/hare2c.py \
		$(CMD_DIR)/hare2c/main.ha \
		$(CMD_DIR)/hare2c/arena.ha \
		$(CMD_DIR)/hare2c/ast.ha \
		$(CMD_DIR)/hare2c/dict.ha \
		$(CMD_DIR)/hare2c/parser.ha \
		$(CMD_DIR)/hare2c/pattern.ha \
		$(CMD_DIR)/hare2c/reader.ha \
		$(CMD_DIR)/hare2c/rules.ha \
		$(CMD_DIR)/hare2c/strbuf.ha \
		$(CMD_DIR)/hare2c/token.ha \
		$(CMD_DIR)/hare2c/transform.ha \
		-o $(BUILD_DIR)/hare2c.c
	$(CC) $(CFLAGS) $(BUILD_DIR)/hare2c.c $(LIB_DIR)/hare/rt.c -o $(HARE2C)
	@echo "Built: $(HARE2C)"

# Build self-hosted Pika transpiler
pika2c: $(PIKA2C)

$(PIKA2C): $(BUILD_DIR) $(CMD_DIR)/hare2c.py $(CMD_DIR)/pika2c/*.pka
	@echo "Building pika2c transpiler..."
	$(PYTHON) $(CMD_DIR)/hare2c.py -p pika \
	$(CMD_DIR)/pika2c/*.pka \
	-o $(BUILD_DIR)/pika2c.c
	$(CC) $(CFLAGS) $(BUILD_DIR)/pika2c.c $(LIB_DIR)/pika/rt.c -o $(PIKA2C)
	@echo "Built: $(PIKA2C)"

# Run all tests
check:
	@echo "Running test suite..."
	@bash $(TEST_DIR)/test_hare_tests.sh || true
	@echo ""
	@cd $(TEST_DIR) && bash test_hare2c_py.sh
	@echo ""
	@cd $(TEST_DIR) && bash test_hare2c.sh
	@echo ""
	@cd $(TEST_DIR) && bash test_pika2c.sh

# Run SYCL backend tests (Intel + CUDA if available)
check-sycl: pika2c
	@bash $(TEST_DIR)/test_sycl_cpu.sh
	@bash $(TEST_DIR)/test_sycl_cuda.sh 2>/dev/null || true

# Run JavaScript backend tests (pika2c -> JS -> node)
check-js: pika2c
	$(NODE) $(TEST_DIR)/test_pika_js.js
	$(NODE) $(TEST_DIR)/test_glsl_node.js

# WASM demo smoke test
check-wasm:
	bash $(WASM_DIR)/test_wasm.sh

# Run cross-module compilation tests
check-module: pika2c
	@bash $(TEST_DIR)/test_modules.sh

# Run GLSL backend tests
check-glsl: pika2c
	bash $(TEST_DIR)/test_glsl.sh

# Build WASM versions
wasm:
	@echo "Building WASM versions..."
	@bash $(WASM_DIR)/build_wasm_hare.sh
	@bash $(WASM_DIR)/build_wasm_pika_js.sh

# BOLT optimization targets
optimize: optimize-hare2c optimize-pika2c
	@echo "Both transpilers optimized with BOLT"

optimize-hare2c: $(BUILD_DIR)
	@echo "=== BOLT optimizing hare2c ==="
	@echo "Step 1: Building hare2c with relocations (no strip)..."
	$(PYTHON) $(CMD_DIR)/hare2c.py \
		$(CMD_DIR)/hare2c/main.ha \
		$(CMD_DIR)/hare2c/arena.ha \
		$(CMD_DIR)/hare2c/ast.ha \
		$(CMD_DIR)/hare2c/dict.ha \
		$(CMD_DIR)/hare2c/parser.ha \
		$(CMD_DIR)/hare2c/pattern.ha \
		$(CMD_DIR)/hare2c/reader.ha \
		$(CMD_DIR)/hare2c/rules.ha \
		$(CMD_DIR)/hare2c/strbuf.ha \
		$(CMD_DIR)/hare2c/token.ha \
		$(CMD_DIR)/hare2c/transform.ha \
		-o $(BUILD_DIR)/hare2c.c
	$(CC) $(CFLAGS_BOLT) $(BUILD_DIR)/hare2c.c $(LIB_DIR)/hare/rt.c -o $(BUILD_DIR)/hare2c.prof
	@echo "Step 2: Profiling with perf ($(PROFILE_ITERATIONS) iterations)..."
	$(PERF) record -e cycles:u -o $(BUILD_DIR)/hare2c.perf.data -- \
		bash -c 'for i in $$(seq 1 $(PROFILE_ITERATIONS)); do \
			cat $(CMD_DIR)/hare2c/*.ha | $(BUILD_DIR)/hare2c.prof > /dev/null; \
		done'
	@echo "Step 3: Converting profile to BOLT format..."
	$(PERF2BOLT) -p $(BUILD_DIR)/hare2c.perf.data -o $(BUILD_DIR)/hare2c.fdata \
		-nl $(BUILD_DIR)/hare2c.prof 2>&1 | tail -5
	@echo "Step 4: Running BOLT optimization..."
	$(LLVM_BOLT) $(BUILD_DIR)/hare2c.prof -o $(BUILD_DIR)/hare2c.bolt \
		-data=$(BUILD_DIR)/hare2c.fdata $(BOLT_OPTS)
	@echo "Step 5: Stripping final binary..."
	strip -s $(BUILD_DIR)/hare2c.bolt -o $(HARE2C)
	rm -f $(BUILD_DIR)/hare2c.prof $(BUILD_DIR)/hare2c.perf.data $(BUILD_DIR)/hare2c.fdata
	@echo "Optimized: $(HARE2C)"
	@ls -la $(HARE2C)

optimize-pika2c: $(BUILD_DIR)
	@echo "=== BOLT optimizing pika2c ==="
	@echo "Step 1: Building pika2c with relocations (no strip)..."
	$(PYTHON) $(CMD_DIR)/hare2c.py -p pika \
		$(CMD_DIR)/pika2c/*.pka \
		-o $(BUILD_DIR)/pika2c.c
	$(CC) $(CFLAGS_BOLT) $(BUILD_DIR)/pika2c.c $(LIB_DIR)/pika/rt.c -o $(BUILD_DIR)/pika2c.prof
	@echo "Step 2: Profiling with perf ($(PROFILE_ITERATIONS) iterations)..."
	$(PERF) record -e cycles:u -o $(BUILD_DIR)/pika2c.perf.data -- \
		bash -c 'for i in $$(seq 1 $(PROFILE_ITERATIONS)); do \
			cat $(CMD_DIR)/pika2c/*.pka | $(BUILD_DIR)/pika2c.prof > /dev/null; \
		done'
	@echo "Step 3: Converting profile to BOLT format..."
	$(PERF2BOLT) -p $(BUILD_DIR)/pika2c.perf.data -o $(BUILD_DIR)/pika2c.fdata \
		-nl $(BUILD_DIR)/pika2c.prof 2>&1 | tail -5
	@echo "Step 4: Running BOLT optimization..."
	$(LLVM_BOLT) $(BUILD_DIR)/pika2c.prof -o $(BUILD_DIR)/pika2c.bolt \
		-data=$(BUILD_DIR)/pika2c.fdata $(BOLT_OPTS)
	@echo "Step 5: Stripping final binary..."
	strip -s $(BUILD_DIR)/pika2c.bolt -o $(PIKA2C)
	rm -f $(BUILD_DIR)/pika2c.prof $(BUILD_DIR)/pika2c.perf.data $(BUILD_DIR)/pika2c.fdata
	@echo "Optimized: $(PIKA2C)"
	@ls -la $(PIKA2C)

install:
	install -m755 $(BUILD_DIR)/hare2c $(PREFIX)/bin/hare2c
	install -m755 $(BUILD_DIR)/pika2c $(PREFIX)/bin/pika2c

uninstall:
	rm $(PREFIX)/bin/hare2c
	rm $(PREFIX)/bin/pika2c

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(TEST_DIR)/*.o $(TEST_DIR)/*.c $(TEST_DIR)/*.out
	rm -f *.o *.out
	@echo "Cleaned build artifacts"

.PHONY: 