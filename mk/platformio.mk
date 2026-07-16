# =============================================================================
# Builder fragment: PlatformIO
# =============================================================================
# The default build tool. Compiles the canonical library via platformio.ini, and
# adds an offline package cache for air-gapped / restricted-network builds.
#
# The generic build/upload/monitor verbs bind here only when BUILDER=platformio;
# the offline-cache targets (pio-prime/pio-bundle/build-offline/pio-clean-vendor)
# and check-drive are always available while this fragment ships.
# =============================================================================

PIO_ENV  := teensy41
PIO      := $(shell command -v pio 2>/dev/null || command -v platformio 2>/dev/null)
PIO_NAME := PlatformIO
PIO_HINT := pipx install platformio (or brew install platformio).

# Firmware cross-compile env hygiene. GCC-family compilers - including the Teensy
# arm-none-eabi toolchain - honor CPATH/*_INCLUDE_PATH/LIBRARY_PATH. Some host
# setups (e.g. Alire's Ada toolchain) export CPATH=$SDKROOT/usr/include, which
# leaks host SDK headers into the ARM/newlib firmware build and fails the compile
# (__sbuf/__sFILE redefined). Strip exactly those vars for firmware invocations
# with a TARGETED `env -u` (never `env -i`, which would drop PATH/proxy/CA/
# PLATFORMIO_CORE_DIR that offline & corporate builds depend on). Host tests are
# NOT sanitized: a host SDK on CPATH is harmless for a native compile.
PIO_ENV_SANITIZE := env -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
                        -u OBJC_INCLUDE_PATH -u LIBRARY_PATH

# Offline cache. A project-local core dir holds the platform, toolchain, framework
# and tools so firmware can build without the registry. Prime it on a connected
# machine of the SAME OS/arch as the offline target; bundles are OS/arch-specific.
PIO_VENDOR := vendor/platformio
PIO_BUNDLE := teensy-pio-cache-$(HOST_OS)-$(ARCH).tar.gz
ifneq ($(wildcard $(PIO_VENDOR)),)
  PIO_CORE_ENV := PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR))
else
  PIO_CORE_ENV :=
endif

.PHONY: check-pio check-drive build-debug pio-prime pio-bundle build-offline pio-clean-vendor
check-pio:
	$(call need,PIO)

build-debug: check-pio check-drive ## Compile the firmware with debug symbols (env:teensy41_debug; live on-chip debug needs an SWD probe)
	@printf "$(BLUE)Building DEBUG firmware (teensy41_debug: -Og -g3, symbols)...$(NC)\n"
	@printf "$(YELLOW)Note: LOCAL debug build; release env:teensy41 is unchanged. Live on-chip debug needs an external SWD/J-Link probe - see DEBUGGING.md.$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV)_debug

# On Windows, PlatformIO unpacks packages via os.path.relpath, which raises
# "Paths don't have the same drive" when the project-local core dir and Windows
# TEMP live on different drives - e.g. a checkout on a mapped/shared drive (W:)
# while TEMP is on C:. This guard warns loudly before any pio package operation;
# it never blocks. Inert on macOS/Linux and on a same-drive Windows checkout.
check-drive:
ifeq ($(HOST_OS),Windows)
	@core="$$(cygpath -w '$(abspath $(PIO_VENDOR))' 2>/dev/null)"; \
	tmp="$$(cygpath -w "$${TEMP:-$${TMP:-C:\\Windows\\Temp}}" 2>/dev/null)"; \
	cd=$$(printf '%.1s' "$$core" | tr '[:lower:]' '[:upper:]'); \
	td=$$(printf '%.1s' "$$tmp"  | tr '[:lower:]' '[:upper:]'); \
	if [ -n "$$cd" ] && [ -n "$$td" ] && [ "$$cd" != "$$td" ]; then \
		printf "$(RED)$(BOLD)!! Cross-drive PlatformIO build: core on $$cd: but TEMP on $$td:.$(NC)\n"; \
		printf "$(YELLOW)   PlatformIO may abort package unpack with \"Paths don't have the same drive\".$(NC)\n"; \
		printf "$(YELLOW)   Fix: check out the project on the same drive as TEMP (usually C:).$(NC)\n"; \
	fi
endif

pio-prime: check-pio check-drive ## Populate vendor/platformio and prove it builds (run on a connected, same-OS/arch machine)
	@printf "$(YELLOW)Priming $(PIO_VENDOR) - run on a machine WITH network and the SAME OS/arch as the offline target.$(NC)\n"
	@mkdir -p $(PIO_VENDOR)
	-@PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR)) $(PIO) settings set enable_telemetry No >/dev/null 2>&1 || true
	@printf "$(BLUE)Installing packages for $(PIO_ENV)...$(NC)\n"
	PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR)) $(PIO) pkg install -e $(PIO_ENV)
	@printf "$(BLUE)Verification build against the local core...$(NC)\n"
	$(PIO_ENV_SANITIZE) PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR)) $(PIO) run -e $(PIO_ENV)
	@printf "$(GREEN)Primed and verified.$(NC) Bundle it with 'make pio-bundle'.\n"

pio-bundle: ## Pack vendor/platformio into a transferable OS/arch-named .tar.gz
	@[ -d "$(PIO_VENDOR)" ] || $(call die,Nothing to bundle: $(PIO_VENDOR) is missing. Run 'make pio-prime' first.)
	@printf "$(BLUE)Bundling $(PIO_VENDOR) -> $(PIO_BUNDLE)$(NC)\n"
	tar -czf $(PIO_BUNDLE) -C $(dir $(PIO_VENDOR)) $(notdir $(PIO_VENDOR))
	@printf "$(GREEN)Built %s$(NC) (%s)\n" "$(PIO_BUNDLE)" "$$(du -h $(PIO_BUNDLE) | cut -f1)"

build-offline: check-pio check-drive ## Build firmware using ONLY vendor/platformio (cache-only; no install/update)
	@[ -d "$(PIO_VENDOR)" ] || $(call die,No project-local core at $(PIO_VENDOR). Prime it ('make pio-prime') on a same-OS/arch machine or unpack a bundle into vendor/.)
	@printf "$(BLUE)Cache-only build using $(PIO_VENDOR)...$(NC)\n"
	@printf "$(YELLOW)Note: PlatformIO has no hard offline flag. This uses only the local core and does not intentionally install/update; verify true no-network on the restricted machine.$(NC)\n"
	$(PIO_ENV_SANITIZE) PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR)) $(PIO) run -e $(PIO_ENV)

pio-clean-vendor: ## Remove only vendor/platformio and generated cache archives
	@printf "$(YELLOW)Removing $(PIO_VENDOR) and cache archives...$(NC)\n"
	rm -rf $(PIO_VENDOR)
	rm -f teensy-pio-cache-*.tar.gz

# --- aggregate contributions (always, whether or not platformio is selected)
clean::
	-@[ -n "$(PIO)" ] && $(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV) -t clean >/dev/null 2>&1 || true
	rm -rf .pio

check-tools::
	$(call report,PIO)

# --- generic verb bindings (only when this is the selected builder)
ifeq ($(BUILDER),platformio)
HEX ?= .pio/build/$(PIO_ENV)/firmware.hex
.PHONY: build upload burn monitor
build: check-pio check-drive
	@printf "$(BLUE)Building firmware ($(PIO_ENV))...$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV)

upload: check-pio check-drive
	@printf "$(BLUE)Uploading firmware to Teensy...$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV) -t upload

burn: upload

monitor: check-pio
	$(PIO_CORE_ENV) $(PIO) device monitor
endif
