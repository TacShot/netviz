# eBPF Network Monitor Makefile

# Build tools
CLANG = clang
LLC = llc
CC = gcc

# Kernel headers location (adjust if needed)
KERNEL_HEADERS = /usr/src/linux-headers-$(shell uname -r)

# Compiler flags
CFLAGS = -O2 -target bpf -D__TARGET_ARCH_x86 -I$(KERNEL_HEADERS)/arch/x86/include/generated/uapi -I$(KERNEL_HEADERS)/arch/x86/include/generated -I$(KERNEL_HEADERS)/arch/x86/include/uapi -I$(KERNEL_HEADERS)/include/uapi -I$(KERNEL_HEADERS)/include/generated/uapi -I$(KERNEL_HEADERS)/include

# Output files
OBJ_NAME = network_monitor
OBJ_FILE = $(OBJ_NAME).o

# Source files
SRCS = network_monitor.c

.PHONY: all clean install

all: $(OBJ_FILE)

$(OBJ_FILE): $(SRCS)
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ_FILE)

install: $(OBJ_FILE)
	cp $(OBJ_FILE) /tmp/

# Debug build with verbose output
debug: CFLAGS += -g -DDEBUG
debug: $(OBJ_FILE)

# Help target
help:
	@echo "Available targets:"
	@echo "  all     - Build eBPF object file"
	@echo "  clean   - Remove build artifacts"
	@echo "  install - Copy object file to /tmp/"
	@echo "  debug   - Build with debug symbols"
	@echo "  help    - Show this help message"