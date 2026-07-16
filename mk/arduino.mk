# =============================================================================
# Builder fragment: Arduino CLI
# =============================================================================
# A command-line build tool (NOT the Arduino IDE, which is unsupported). Compiles
# the SAME canonical library ($(CANON_LIB)) as every other builder; the sketch
# arduino/teensy_sos/teensy_sos.ino is only a thin composition root.
#
# Teensy/Teensyduino defaults to GNU C++17, but this project requires GNU C++20,
# so the build REPLACES build.flags.cpp with the validated C++20 flag set. The
# output/input dirs are ABSOLUTE on purpose: a relative input dir makes the Teensy
# loader fail to read the compiled sketch on upload.
#
# Naming: verb-first, builder-suffixed (build-arduino, upload-arduino, ...). The
# generic build/upload/monitor verbs in the root alias to the -$(BUILDER) target.
# HEX_arduino is this builder's flash image, picked up by the board's `flash`.
# =============================================================================

ARDUINO_CLI      := $(shell command -v arduino-cli 2>/dev/null)
ARDUINO_CLI_NAME := arduino-cli
ARDUINO_CLI_HINT := brew install arduino-cli (or https://arduino.github.io/arduino-cli/); only for BUILDER=arduino targets.
ARDUINO_FQBN     := teensy:avr:teensy41
# Reviewed & hardware-validated Teensy core version. Override deliberately to
# qualify a newer one: make ARDUINO_CORE_VERSION=<ver> build-arduino
ARDUINO_CORE_VERSION := 1.62.0
ARDUINO_SKETCH   := arduino/teensy_sos
ARDUINO_BUILD    := $(abspath arduino/teensy_sos/build)
ARDUINO_LIB      := $(abspath lib/TeensySos)
HEX_arduino      := $(ARDUINO_BUILD)/$(notdir $(ARDUINO_SKETCH)).ino.hex
# GNU C++20 flags for the Teensy core, validated on hardware. This REPLACES the
# core's default build.flags.cpp (which selects gnu++17).
ARDUINO_CPP_FLAGS := -std=gnu++20 -fno-exceptions -fpermissive -fno-rtti \
                     -fno-threadsafe-statics -felide-constructors \
                     -Wno-error=narrowing -Wno-psabi -Wno-maybe-uninitialized
# Dynamic Teensy port detection - never hardcode usb:100000. Pick the port whose
# row advertises the teensy41 FQBN; override with ARDUINO_PORT=... Evaluated
# lazily (only upload needs it), so unrelated targets never query the USB bus.
ARDUINO_PORT ?= $(shell $(ARDUINO_CLI) board list 2>/dev/null | awk 'tolower($$0) ~ /teensy:avr:teensy41/ {print $$1; exit}')

.PHONY: check-arduino build-arduino upload-arduino monitor-arduino clean-arduino
check-arduino: ## Verify arduino-cli, the Teensy core, and the teensy41 board are available
	$(call need,ARDUINO_CLI)
	@printf "$(BLUE)%s$(NC)\n" "$$($(ARDUINO_CLI) version)"
	@if ! $(ARDUINO_CLI) core list 2>/dev/null | grep -q '^teensy:avr'; then \
		printf "$(RED)Teensy core (teensy:avr) is not installed.$(NC) Install it (see docs/BUILD.md):\n"; \
		printf "  arduino-cli config add board_manager.additional_urls https://www.pjrc.com/teensy/package_teensy_index.json\n"; \
		printf "  arduino-cli core update-index && arduino-cli core install teensy:avr@$(ARDUINO_CORE_VERSION)\n"; \
		exit 1; \
	fi
	@installed="$$($(ARDUINO_CLI) core list 2>/dev/null | awk '/^teensy:avr/{print $$2; exit}')"; \
	if [ "$$installed" != "$(ARDUINO_CORE_VERSION)" ]; then \
		printf "$(RED)Teensy core is %s, but the reviewed/validated version is $(ARDUINO_CORE_VERSION).$(NC)\n" "$$installed"; \
		printf "  Install it:  arduino-cli core install teensy:avr@$(ARDUINO_CORE_VERSION)\n"; \
		printf "  Or qualify the installed one:  make ARDUINO_CORE_VERSION=%s build-arduino\n" "$$installed"; \
		exit 1; \
	fi; \
	printf "$(GREEN)Teensy core:$(NC) %s (validated)\n" "$$installed"
	@if ! $(ARDUINO_CLI) board details --fqbn $(ARDUINO_FQBN) >/dev/null 2>&1; then \
		printf "$(RED)Board $(ARDUINO_FQBN) is not known to arduino-cli.$(NC) Is the Teensy core installed correctly?\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Board OK:$(NC) $(ARDUINO_FQBN)\n"

build-arduino: check-arduino ## Compile the sketch with GNU C++20 against the canonical library (Arduino CLI)
	@printf "$(BLUE)Arduino CLI build ($(ARDUINO_FQBN), GNU C++20)...$(NC)\n"
	@rm -rf "$(ARDUINO_BUILD)"
	@mkdir -p "$(ARDUINO_BUILD)"
	$(ARDUINO_CLI) compile \
		--clean \
		--fqbn $(ARDUINO_FQBN) \
		--library "$(ARDUINO_LIB)" \
		--build-property "build.flags.cpp=$(ARDUINO_CPP_FLAGS)" \
		--output-dir "$(ARDUINO_BUILD)" \
		"$(ARDUINO_SKETCH)"
	@printf "$(GREEN)Arduino build OK$(NC) -> $(ARDUINO_BUILD)\n"

upload-arduino: build-arduino ## Build, then flash the connected Teensy via Arduino CLI (dynamic port; override ARDUINO_PORT=...)
	@port="$(ARDUINO_PORT)"; \
	if [ -z "$$port" ]; then \
		printf "$(RED)No Teensy port detected.$(NC) Connect the board, or pass ARDUINO_PORT=... (see 'arduino-cli board list').\n"; \
		exit 1; \
	fi; \
	printf "$(BLUE)Arduino CLI upload to %s (press the Teensy Program button if prompted)...$(NC)\n" "$$port"; \
	$(ARDUINO_CLI) upload \
		-p "$$port" \
		--fqbn $(ARDUINO_FQBN) \
		--input-dir "$(ARDUINO_BUILD)" \
		"$(ARDUINO_SKETCH)"

monitor-arduino: ## Open the Arduino CLI serial monitor (dynamic port; override ARDUINO_PORT=...)
	@port="$(ARDUINO_PORT)"; \
	[ -n "$$port" ] || { printf "$(RED)No Teensy port detected.$(NC) Pass ARDUINO_PORT=...\n"; exit 1; }; \
	$(ARDUINO_CLI) monitor -p "$$port"

clean-arduino: ## Remove the Arduino CLI build output
	@printf "$(YELLOW)Cleaning Arduino build artifacts...$(NC)\n"
	rm -rf "$(ARDUINO_BUILD)"

check-tools::
	$(call report,ARDUINO_CLI)
