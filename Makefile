# Variables
BINARY_NAME = daw
BUILD_DIR = zig-out/bin
PID_FILE = /tmp/daw.pid
TRACKS_FILE = /tmp/daw-tracks-v2.txt

.PHONY: all build run stop clean list-devices

# Default target: build the binary
all: build

# 1. Compile the app using Zig's native build system
build:
	@echo "🔨 Compiling with Zig..."
	@zig build -Doptimize=ReleaseFast

# 2. Execute ./daw start command to run the backend loop in the background
start: build
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "⚠️ DAW backend is already running (PID: $$(cat $(PID_FILE)))"; \
	else \
		rm -f $(PID_FILE) $(TRACKS_FILE) /tmp/daw-tracks.txt; \
		echo "🚀 Starting DAW backend daemon..."; \
		./$(BUILD_DIR)/$(BINARY_NAME) start > /tmp/daw.log 2>&1 & echo $$! > $(PID_FILE); \
		sleep 1; \
		if kill -0 $$(cat $(PID_FILE)) 2>/dev/null && [ -f $(TRACKS_FILE) ]; then \
			echo "✅ DAW backend is running in background (PID: $$(cat $(PID_FILE)))"; \
		else \
			echo "❌ DAW backend failed to start. See /tmp/daw.log"; \
			rm -f $(PID_FILE); \
			exit 1; \
		fi; \
	fi

# 3. Stop the backend application safely
stop:
	@if [ -f $(PID_FILE) ]; then \
		PID=$$(cat $(PID_FILE)); \
		echo "🛑 Stopping DAW backend (PID: $$PID)..."; \
		kill $$PID 2>/dev/null || true; \
		rm -f $(PID_FILE) $(TRACKS_FILE) /tmp/daw-tracks.txt; \
		echo "✅ Stopped."; \
	else \
		echo "🤷 No running DAW backend found."; \
		rm -f $(TRACKS_FILE) /tmp/daw-tracks.txt; \
	fi

# Quick shortcut to see what tracks are active (maps to step 4 of your journey)
tracks-list:
	@./$(BUILD_DIR)/$(BINARY_NAME) tracks list

# Quick shortcut to see available devices (maps to step 3 of your journey)
devices-list:
	@./$(BUILD_DIR)/$(BINARY_NAME) devices list

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf .zig-cache zig-out $(PID_FILE) $(TRACKS_FILE) /tmp/daw-tracks.txt
