# Makefile
.PHONY: all build release debug test clean run dist help

ZIG ?= zig
NAME := zenith

all: release

# Default: build all 14 cross-compilation targets
build:
	$(ZIG) build

release:
	$(ZIG) build -Doptimize=ReleaseSmall

debug:
	$(ZIG) build -Doptimize=Debug

test:
	$(ZIG) build test

run:
	$(ZIG) build run

clean:
	rm -rf zig-out .zig-cache

# dist is now the same as release (default builds all platforms)
dist: release

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "  all       Build all platforms, optimized (default)"
	@echo "  build     Build all platforms with default options"
	@echo "  release   Build all platforms, ReleaseSmall"
	@echo "  debug     Build all platforms, Debug"
	@echo "  test      Run unit tests (native)"
	@echo "  run       Build and run (native)"
	@echo "  clean     Remove build artifacts"
	@echo "  dist      Alias for release"
