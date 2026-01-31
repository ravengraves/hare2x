.PHONY: check clean
.ONESHELL:

ROOT := ..
PIKA2C := $(ROOT)/build/pika2c
RT := $(ROOT)/lib/pika/rt.c

CC = clang
CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion \
	-Wno-gnu-auto-type -Wno-unused-function -Wno-unused-variable \
	-Wno-gnu-statement-expression -Wno-parentheses-equality

DOC_TESTS := $(wildcard test/*.pka)

check:
	set -e
	if [ -z "$(DOC_TESTS)" ]; then
		echo "No doc tests found under docs/test/*.pka"
		exit 1
	fi

	$(MAKE) -C $(ROOT) pika2c

	tmp=$$(mktemp -d)
	trap 'rm -rf "$$tmp"' EXIT

	for f in $(DOC_TESTS); do
		name=$$(basename "$$f" .pka)
		"$(PIKA2C)" < "$$f" > "$$tmp/$$name.c"
		$(CC) $(CFLAGS) "$$tmp/$$name.c" "$(RT)" -o "$$tmp/$$name.bin"
		"$$tmp/$$name.bin" < /dev/null > /dev/null 2>&1
	done

	@echo "Tests Passed!"

clean:
	@true

.Phony: check clean
