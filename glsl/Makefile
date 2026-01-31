CC ?= cc
PKG_CONFIG ?= pkg-config

CFLAGS ?= -O2 -Wall -Wextra -I.
GLFW_CFLAGS := $(shell $(PKG_CONFIG) --cflags glfw3)
GLFW_LIBS := $(shell $(PKG_CONFIG) --libs glfw3)
LIBS := $(GLFW_LIBS) -lGLESv2 -lEGL -lm

TARGET := triangle_demo
OBJ := triangle_gles.o terminal_view.o

Xvfb := $(shell command -v xvfb-run 2>/dev/null)
RUNNER :=
ifeq ($(DISPLAY),)
  ifneq ($(Xvfb),)
    RUNNER := xvfb-run -s "-screen 0 1280x720x24"
  endif
endif

.PHONY: all clean check run

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(CFLAGS) $(GLFW_CFLAGS) -o $@ $^ $(LIBS)

triangle_gles.o: triangle_gles.c terminal_view.h
	$(CC) $(CFLAGS) $(GLFW_CFLAGS) -c -o $@ $<

terminal_view.o: terminal_view.c terminal_view.h
	$(CC) $(CFLAGS) -c -o $@ $<

run: $(TARGET)
	@if [ -z "$(VERTEX_SHADER)" ] || [ -z "$(FRAGMENT_SHADER)" ]; then \
		echo "Set VERTEX_SHADER and FRAGMENT_SHADER to run."; \
		exit 1; \
	fi
	$(RUNNER) ./$(TARGET) --seconds 10 \
		--vertex "$(VERTEX_SHADER)" --fragment "$(FRAGMENT_SHADER)"

check: $(TARGET)
	@if [ -z "$(VERTEX_SHADER)" ] || [ -z "$(FRAGMENT_SHADER)" ]; then \
		echo "Set VERTEX_SHADER and FRAGMENT_SHADER to check."; \
		exit 1; \
	fi
	LIBGL_ALWAYS_SOFTWARE=1 $(RUNNER) ./$(TARGET) --seconds 0.2 \
		--terminal --terminal-fps 1 \
		--vertex "$(VERTEX_SHADER)" --fragment "$(FRAGMENT_SHADER)"

clean:
	rm -f $(TARGET) $(OBJ)
