# ToolRunner Makefile

.PHONY: all build demo clean test lint

# Crystal build flags required for ExecutionContext::Isolated
CRYSTAL_FLAGS = -Dpreview_mt -Dexecution_context

# Default target
all: build

# Build the demo binary
demo: bin/demo

bin/demo: examples/demo.cr
	@mkdir -p bin
	crystal build $(CRYSTAL_FLAGS) -o $@ $<

# Build everything
build: bin/demo

# Run the demo with a test command
test-demo: bin/demo
	./bin/demo "echo 'Hello from ToolRunner!'"

# Run specs
test:
	crystal spec $(CRYSTAL_FLAGS)

# Run linter
lint:
	ameba

# Fix linting issues
lint-fix:
	ameba --fix

# Clean build artifacts
clean:
	rm -rf bin

# Help
help:
	@echo "ToolRunner Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make build    - Build the demo binary"
	@echo "  make demo     - Build the demo binary (same as build)"
	@echo "  make test-demo - Build and run demo with test command"
	@echo "  make test     - Run the test suite"
	@echo "  make lint     - Run linter"
	@echo "  make lint-fix - Fix linting issues automatically"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make help     - Show this help message"
