# =============================================================================
# Board fragment: Teensy 4.1
# =============================================================================
# Board-specific, build-tool-agnostic concerns. Today that is the air-gap flash
# path: burn a prebuilt .hex with the standalone Teensy loader - NO build tool
# and NO network. This is the cross-domain path: build the .hex on a connected
# machine, transfer only the small ASCII .hex across the software bridge, and
# flash it inside the enclave. Each builder exports HEX_<builder>; the root resolves
# HEX ?= $(HEX_$(BUILDER)) to the selected builder's output, which this target
# consumes. Override with HEX=/path to flash any prebuilt image.
# =============================================================================

BOARD_MCU     := TEENSY41
TEENSY_LOADER := $(shell command -v teensy_loader_cli 2>/dev/null)
TEENSY_LOADER_NAME := teensy_loader
TEENSY_LOADER_HINT := brew install teensy_loader_cli (or build from github.com/PaulStoffregen/teensy_loader_cli); only for 'make flash'.

.PHONY: flash
flash: ## Flash a prebuilt .hex with teensy_loader_cli (air-gap; no build tool). Override HEX=/path.
	$(call need,TEENSY_LOADER)
	@[ -n "$(HEX)" ] || $(call die,No HEX set. Pass HEX=/path/to/firmware.hex (or select a BUILDER whose build produces one).)
	@[ -f "$(HEX)" ] || $(call die,No .hex at '$(HEX)'. Build it first or pass HEX=/path/to/firmware.hex.)
	@printf "$(BLUE)Flashing %s to $(BOARD_MCU) (press the on-board button if prompted)...$(NC)\n" "$(HEX)"
	$(TEENSY_LOADER) --mcu=$(BOARD_MCU) -w -v "$(HEX)"

check-tools::
	$(call report,TEENSY_LOADER)
