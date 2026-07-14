# =============================================================================
# Project Makefile
# =============================================================================
# Project: teensy_sos (SOS Morse blinker on an RGB LED)
# Purpose: Clean-room Teensy 4.1 starter/reference project with a hexagonal,
#          port/adapter architecture and a cross-platform, offline-capable build.
#
# This Makefile provides:
#   - Firmware targets   (build, upload/burn, monitor, clean, rebuild) via PlatformIO
#   - Offline cache      (pio-prime, pio-bundle, build-offline) for air-gapped builds
#   - Air-gap flashing   (flash HEX=...) via teensy_loader_cli, no PlatformIO needed
#   - Host test targets  (test, test-core, test-morse, test-sos) via the C++ compiler
#   - Tooling            (check-tools) and packaging (package)
#
# Firmware needs PlatformIO (`pipx install platformio` or `brew install platformio`).
# Host tests need only a C++20 compiler - no Teensy toolchain.
# =============================================================================

PROJECT_NAME := teensy_sos

.PHONY: all help build build-debug build-offline upload burn monitor clean rebuild flash \
        arduino-check arduino-build arduino-upload arduino-clean build-all \
        pio-prime pio-bundle pio-clean-vendor \
        test test-core test-morse test-sos debug-host \
        diagrams diagrams-clean specs docs sanitize-media verify-media \
        check-tools package check-pio check-drive

# =============================================================================
# Colors
# =============================================================================
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
BOLD   := \033[1m
NC     := \033[0m

# =============================================================================
# Tools & configuration
# =============================================================================
PIO_ENV  := teensy41
PIO      := $(shell command -v pio 2>/dev/null || command -v platformio 2>/dev/null)

# Host platform detection. On Windows - including MSYS2/mingw64 shells - the OS
# environment variable is Windows_NT; elsewhere we fall back to uname. This drives
# the host-test executable suffix and the default host compiler.
ifeq ($(OS),Windows_NT)
  HOST_OS := Windows
  EXE     := .exe
else
  HOST_OS := $(shell uname -s)
  EXE     :=
endif

# Host compiler. Honor an explicit CXX from the environment or command line; only
# when CXX is still Make's built-in default do we pick the project standard (GNU
# GCC): g++ on Windows/MSYS2 mingw64, c++ elsewhere (the clang or gcc driver).
ifeq ($(origin CXX),default)
  ifeq ($(OS),Windows_NT)
    CXX := g++
  else
    CXX := c++
  endif
endif

# The canonical headers live in the TeensySos library (lib/TeensySos/src), shared
# by both the PlatformIO and Arduino composition roots; host tests include them
# straight from there - no Teensy toolchain, no duplication.
HOST_CXXFLAGS := -std=c++20 -Wall -Wextra -Ilib/TeensySos/src
HOST_BUILD    := .build-host

# Host debugging (LOCAL development only). `make debug-host` builds one host suite
# with debugger-friendly flags and drops into the platform debugger. -Og keeps the
# code optimized-but-debuggable, -g3 includes macro info, -fno-omit-frame-pointer
# keeps backtraces reliable. This debugs the DOMAIN/APPLICATION logic on the host -
# it is NOT firmware-on-the-chip debugging (the Teensy 4.1 has no on-board probe;
# see DEBUGGING.md). Pick the suite with SUITE=core|morse|sos (default sos) and
# override the debugger with DEBUGGER=... if needed.
HOST_DBGFLAGS := -Og -g3 -fno-omit-frame-pointer
SUITE         ?= sos
ifeq ($(SUITE),core)
  DBG_SRC := test/test_core.cpp
else ifeq ($(SUITE),morse)
  DBG_SRC := test/test_morse.cpp
else ifeq ($(SUITE),sos)
  DBG_SRC := test/test_sos_controller.cpp
else
  DBG_SRC :=
endif
# Default debugger by host OS: lldb ships with the macOS toolchain; gdb is the
# norm on Linux and MSYS2/mingw64. Override with DEBUGGER=... on the command line.
ifeq ($(HOST_OS),Darwin)
  DEBUGGER ?= lldb
else
  DEBUGGER ?= gdb
endif

# Firmware cross-compile env hygiene. GCC-family compilers - including the Teensy
# arm-none-eabi toolchain - honor CPATH/*_INCLUDE_PATH/LIBRARY_PATH. Some host
# toolchain setups (e.g. Alire's Ada toolchain) export CPATH=$SDKROOT/usr/include,
# which leaks host SDK headers into the ARM/newlib firmware build and fails the
# compile (__sbuf/__sFILE redefined). We strip exactly those include/library-path
# vars for PlatformIO firmware invocations with a TARGETED `env -u` (never `env -i`,
# which would also drop PATH/proxy/CA/PLATFORMIO_CORE_DIR that offline & corporate
# builds depend on). Host tests (`make test`) are NOT sanitized: a host SDK on
# CPATH is harmless - and even wanted - for a native compile.
PIO_ENV_SANITIZE := env -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
                        -u OBJC_INCLUDE_PATH -u LIBRARY_PATH

# PlatformIO offline cache (air-gapped / restricted-network builds). A project-local
# core dir holds the platform, toolchain, framework, and tools so firmware can build
# without fetching from the registry. Prime it on a connected machine of the SAME
# OS/arch as the offline target; bundles are OS/arch-specific. See docs/BUILD.md.
PIO_VENDOR := vendor/platformio
ARCH       := $(shell uname -m 2>/dev/null || echo unknown)
PIO_BUNDLE := teensy-pio-cache-$(HOST_OS)-$(ARCH).tar.gz
# If a project-local core exists, route firmware pio invocations through it.
ifneq ($(wildcard $(PIO_VENDOR)),)
  PIO_CORE_ENV := PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR))
else
  PIO_CORE_ENV :=
endif

# Air-gap flashing: burn a prebuilt .hex with the standalone Teensy loader, with
# NO PlatformIO and NO network. This is the cross-domain path - build the .hex on
# a connected machine, transfer only the small ASCII .hex across the software
# bridge, and flash it inside the enclave. Override the source with HEX=/path.
TEENSY_LOADER := $(shell command -v teensy_loader_cli 2>/dev/null)
HEX           ?= .pio/build/$(PIO_ENV)/firmware.hex

# Arduino CLI (a second, co-equal command-line frontend to PlatformIO). Both
# frontends compile the SAME canonical library (lib/TeensySos); the sketch
# arduino/teensy_sos/teensy_sos.ino is only a thin composition root.
#
# Teensy/Teensyduino defaults to GNU C++17, but this project requires GNU C++20,
# so arduino-build REPLACES build.flags.cpp with the validated C++20 flag set.
# Output/input dirs are ABSOLUTE on purpose: a relative input dir makes the Teensy
# loader fail to read the compiled sketch on upload.
#
# Arduino IDE support is a SEPARATE, not-yet-validated slice - it is NOT provided
# by these targets (Arduino CLI only). See docs/BUILD.md.
ARDUINO_CLI    := $(shell command -v arduino-cli 2>/dev/null)
ARDUINO_FQBN   := teensy:avr:teensy41
# Reviewed & hardware-validated Teensy core version. Override deliberately to
# qualify a newer one: make ARDUINO_CORE_VERSION=<ver> arduino-build
ARDUINO_CORE_VERSION := 1.62.0
ARDUINO_SKETCH := arduino/teensy_sos
ARDUINO_BUILD  := $(abspath arduino/teensy_sos/build)
ARDUINO_LIB    := $(abspath lib/TeensySos)
# GNU C++20 flags for the Teensy core, validated on hardware. This REPLACES the
# core's default build.flags.cpp (which selects gnu++17).
ARDUINO_CPP_FLAGS := -std=gnu++20 -fno-exceptions -fpermissive -fno-rtti \
                     -fno-threadsafe-statics -felide-constructors \
                     -Wno-error=narrowing -Wno-psabi -Wno-maybe-uninitialized
# Dynamic Teensy port detection - never hardcode usb:100000 (it is machine- and
# moment-specific). Pick the port whose row advertises the teensy41 FQBN; override
# with ARDUINO_PORT=... on the command line. Evaluated lazily (only 'arduino-upload'
# needs it), so unrelated targets never query the USB bus.
ARDUINO_PORT   ?= $(shell $(ARDUINO_CLI) board list 2>/dev/null | awk 'tolower($$0) ~ /teensy:avr:teensy41/ {print $$1; exit}')

# Documentation tooling. Diagrams: PlantUML (.puml -> .svg, SVGs are checked in as
# reviewed artifacts). Formal docs: Typst (.typ -> PDF, PDFs are build artifacts).
DIAGRAMS_DIR := docs/diagrams
PUML         := $(wildcard $(DIAGRAMS_DIR)/*.puml)
SVG          := $(PUML:.puml=.svg)
TYPST        := $(shell command -v typst 2>/dev/null)
SPECS_SRC    := $(wildcard docs/specs/*.typ)
PLANTUML_JAR ?=
ifneq ($(shell command -v plantuml 2>/dev/null),)
  PLANTUML := plantuml
else ifneq ($(PLANTUML_JAR),)
  PLANTUML := java -jar $(PLANTUML_JAR)
else
  PLANTUML :=
endif

# Media hygiene. Personal photos/videos carry GPS + device metadata (and iPhone
# videos carry audio + timed-metadata data tracks). `make sanitize-media` strips
# all of it in place so the media in docs/assets/ is safe to commit. Needs exiftool
# for images; exiftool + ffmpeg for video. These are maintenance-only tools - not
# required to build, test, or document the project.
EXIFTOOL     := $(shell command -v exiftool 2>/dev/null)
FFMPEG       := $(shell command -v ffmpeg 2>/dev/null)
ASSET_IMAGES := $(wildcard docs/assets/images/*.jpeg docs/assets/images/*.jpg docs/assets/images/*.png)
ASSET_VIDEOS := $(wildcard docs/assets/videos/*.mov docs/assets/videos/*.mp4)

# =============================================================================
# Default
# =============================================================================
all: help

help: ## Display this help message
	@printf "$(BOLD)$(PROJECT_NAME) - SOS Morse blinker on an RGB LED$(NC)\n\n"
	@printf "$(BOLD)Targets:$(NC)\n"
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"} {printf "  $(CYAN)%-16s$(NC) %s\n", $$1, $$2}'
	@printf "\n$(BOLD)Variables:$(NC)\n"
	@printf "  CXX=%s (host tests)   PIO_ENV=%s   HEX=%s (for 'flash')\n" "$(CXX)" "$(PIO_ENV)" "$(HEX)"

# =============================================================================
# Firmware (PlatformIO)
# =============================================================================
build: check-pio check-drive ## Compile the firmware for Teensy 4.1 (uses vendor/platformio if present)
	@printf "$(BLUE)Building firmware ($(PIO_ENV))...$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV)

build-debug: check-pio check-drive ## Compile the firmware with debug symbols (env:teensy41_debug; live on-chip debug needs an SWD probe)
	@printf "$(BLUE)Building DEBUG firmware (teensy41_debug: -Og -g3 -fno-omit-frame-pointer, symbols)...$(NC)\n"
	@printf "$(YELLOW)Note: this is a LOCAL debug build; the release env:teensy41 is unchanged. Live on-chip$(NC)\n"
	@printf "$(YELLOW)      debugging needs an external SWD/J-Link probe wired to the Teensy - see DEBUGGING.md.$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV)_debug

upload: check-pio check-drive ## Build and flash the firmware to a connected Teensy (via PlatformIO)
	@printf "$(BLUE)Uploading firmware to Teensy...$(NC)\n"
	@if [ -n "$(PIO_CORE_ENV)" ]; then printf "$(CYAN)Using project-local PlatformIO core: $(PIO_VENDOR)$(NC)\n"; fi
	$(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV) -t upload

burn: upload ## Alias for 'upload' (build + flash)

monitor: check-pio ## Open the USB serial monitor
	$(PIO_CORE_ENV) $(PIO) device monitor

clean: ## Remove firmware, host-test, and Arduino CLI build artifacts
	@printf "$(YELLOW)Cleaning build artifacts...$(NC)\n"
	-@[ -n "$(PIO)" ] && $(PIO_ENV_SANITIZE) $(PIO_CORE_ENV) $(PIO) run -e $(PIO_ENV) -t clean >/dev/null 2>&1 || true
	rm -rf .pio $(HOST_BUILD) "$(ARDUINO_BUILD)"

rebuild: clean build ## Clean, then build the firmware

# =============================================================================
# Arduino CLI (second command-line frontend; compiles the SAME canonical library)
# =============================================================================
arduino-check: ## Verify arduino-cli, the Teensy core, and the teensy41 board are available
	@if [ -z "$(ARDUINO_CLI)" ]; then \
		printf "$(RED)arduino-cli not found.$(NC) Install it, then re-run (see docs/BUILD.md):\n"; \
		printf "  macOS: brew install arduino-cli   Linux/Windows: https://arduino.github.io/arduino-cli/\n"; \
		exit 1; \
	fi
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
		printf "  Or qualify the installed one:  make ARDUINO_CORE_VERSION=%s arduino-build\n" "$$installed"; \
		exit 1; \
	fi; \
	printf "$(GREEN)Teensy core:$(NC) %s (validated)\n" "$$installed"
	@if ! $(ARDUINO_CLI) board details --fqbn $(ARDUINO_FQBN) >/dev/null 2>&1; then \
		printf "$(RED)Board $(ARDUINO_FQBN) is not known to arduino-cli.$(NC) Is the Teensy core installed correctly?\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Board OK:$(NC) $(ARDUINO_FQBN)\n"

arduino-build: arduino-check ## Compile the Arduino sketch with GNU C++20 against the canonical library (absolute output dir)
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

arduino-upload: arduino-build ## Build, then flash the connected Teensy via Arduino CLI (dynamic port; override ARDUINO_PORT=...)
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

arduino-clean: ## Remove the Arduino CLI build output
	@printf "$(YELLOW)Cleaning Arduino build artifacts...$(NC)\n"
	rm -rf "$(ARDUINO_BUILD)"

build-all: build arduino-build ## Build the firmware with BOTH CLI frontends (PlatformIO + Arduino)
	@printf "$(GREEN)Both frontends built:$(NC) PlatformIO (.pio) and Arduino CLI ($(ARDUINO_BUILD)).\n"

# =============================================================================
# Air-gap flashing (no PlatformIO, no network)
# =============================================================================
flash: ## Flash a prebuilt .hex with teensy_loader_cli (air-gap path). Override HEX=/path.
	@if [ -z "$(TEENSY_LOADER)" ]; then \
		printf "$(RED)teensy_loader_cli not found.$(NC) Install it (brew install teensy_loader_cli,\n"; \
		printf "or build from https://github.com/PaulStoffregen/teensy_loader_cli) to flash without PlatformIO.\n"; \
		exit 1; \
	fi
	@if [ ! -f "$(HEX)" ]; then \
		printf "$(RED)No .hex at $(HEX).$(NC) Build it ('make build') or pass HEX=/path/to/firmware.hex.\n"; \
		exit 1; \
	fi
	@printf "$(BLUE)Flashing %s to Teensy 4.1 (press the on-board button if prompted)...$(NC)\n" "$(HEX)"
	$(TEENSY_LOADER) --mcu=TEENSY41 -w -v "$(HEX)"

# =============================================================================
# PlatformIO offline cache (air-gapped / restricted-network builds)
# =============================================================================
# The bundle supplies PlatformIO's platform/toolchain/framework PACKAGES, not the
# `pio` executable itself - the target machine still needs PlatformIO Core / `pio`
# installed by an approved method. Cache bundles are OS/arch-specific: prime on the
# same platform family as the offline target.

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
	@if [ ! -d "$(PIO_VENDOR)" ]; then \
		printf "$(RED)Nothing to bundle: $(PIO_VENDOR) is missing.$(NC) Run 'make pio-prime' first.\n"; \
		exit 1; \
	fi
	@printf "$(BLUE)Bundling $(PIO_VENDOR) -> $(PIO_BUNDLE)$(NC)\n"
	tar -czf $(PIO_BUNDLE) -C $(dir $(PIO_VENDOR)) $(notdir $(PIO_VENDOR))
	@printf "$(GREEN)Built %s$(NC) (%s)\n" "$(PIO_BUNDLE)" "$$(du -h $(PIO_BUNDLE) | cut -f1)"

build-offline: check-pio check-drive ## Build firmware using ONLY vendor/platformio (cache-only; no install/update)
	@if [ ! -d "$(PIO_VENDOR)" ]; then \
		printf "$(RED)No project-local core at $(PIO_VENDOR).$(NC) Prime it ('make pio-prime') on a same-OS/arch machine, or unpack a bundle into vendor/.\n"; \
		exit 1; \
	fi
	@printf "$(BLUE)Cache-only build using $(PIO_VENDOR)...$(NC)\n"
	@printf "$(YELLOW)Note: PlatformIO has no hard offline flag. This uses only the local core and does not intentionally install/update; verify true no-network on the restricted machine.$(NC)\n"
	$(PIO_ENV_SANITIZE) PLATFORMIO_CORE_DIR=$(abspath $(PIO_VENDOR)) $(PIO) run -e $(PIO_ENV)

pio-clean-vendor: ## Remove only vendor/platformio and generated cache archives
	@printf "$(YELLOW)Removing $(PIO_VENDOR) and cache archives...$(NC)\n"
	rm -rf $(PIO_VENDOR)
	rm -f teensy-pio-cache-*.tar.gz

# =============================================================================
# Host tests (no Teensy toolchain required)
# =============================================================================
test: test-core test-morse test-sos ## Build & run all host unit tests
	@printf "$(GREEN)All host test suites passed.$(NC)\n"

$(HOST_BUILD):
	@mkdir -p $(HOST_BUILD)

test-core: | $(HOST_BUILD) ## Shared-kernel (Option/Result/FixedQueue) tests
	@printf "$(BLUE)== Core / FixedQueue ==$(NC)\n"
	$(CXX) $(HOST_CXXFLAGS) test/test_core.cpp -o $(HOST_BUILD)/test_core$(EXE)
	@$(HOST_BUILD)/test_core$(EXE)

test-morse: | $(HOST_BUILD) ## Morse encoder (SOS program) tests
	@printf "$(BLUE)== Morse encoder ==$(NC)\n"
	$(CXX) $(HOST_CXXFLAGS) test/test_morse.cpp -o $(HOST_BUILD)/test_morse$(EXE)
	@$(HOST_BUILD)/test_morse$(EXE)

test-sos: | $(HOST_BUILD) ## SosController state-machine tests (fake LED + fake clock)
	@printf "$(BLUE)== SosController ==$(NC)\n"
	$(CXX) $(HOST_CXXFLAGS) test/test_sos_controller.cpp -o $(HOST_BUILD)/test_sos$(EXE)
	@$(HOST_BUILD)/test_sos$(EXE)

debug-host: | $(HOST_BUILD) ## Build a host suite with symbols and launch a debugger (SUITE=core|morse|sos, DEBUGGER=lldb|gdb)
	@if [ -z "$(DBG_SRC)" ]; then \
		printf "$(RED)Unknown SUITE='$(SUITE)'.$(NC) Use SUITE=core, SUITE=morse, or SUITE=sos.\n"; exit 1; \
	fi
	@if ! command -v $(DEBUGGER) >/dev/null 2>&1; then \
		printf "$(RED)Debugger '$(DEBUGGER)' not found.$(NC) See DEBUGGING.md for per-OS install steps\n"; \
		printf "  (macOS: lldb via 'xcode-select --install'; Linux: install gdb; MSYS2: pacman -S mingw-w64-ucrt-x86_64-gdb).\n"; \
		exit 1; \
	fi
	@printf "$(BLUE)Building %s with debug symbols ($(HOST_DBGFLAGS))...$(NC)\n" "$(DBG_SRC)"
	$(CXX) $(HOST_CXXFLAGS) $(HOST_DBGFLAGS) $(DBG_SRC) -o $(HOST_BUILD)/debug_$(SUITE)$(EXE)
	@printf "$(BLUE)Launching $(DEBUGGER) on $(HOST_BUILD)/debug_$(SUITE)$(EXE)$(NC) (run the program with 'run'; quit with 'quit').\n"
	@$(DEBUGGER) $(HOST_BUILD)/debug_$(SUITE)$(EXE)

# =============================================================================
# Documentation (PlantUML diagrams + Typst formal docs)
# =============================================================================
docs: diagrams specs ## Build all documentation (diagrams + spec skeletons)
	@printf "$(GREEN)All documentation built.$(NC)\n"

diagrams: $(SVG) ## Generate SVGs from all docs/diagrams/*.puml

$(DIAGRAMS_DIR)/%.svg: $(DIAGRAMS_DIR)/%.puml
	@if [ -z "$(PLANTUML)" ]; then \
		printf "$(RED)PlantUML not found.$(NC) Install it (brew install plantuml) or set PLANTUML_JAR=<path>.\n"; \
		exit 1; \
	fi
	@printf "$(BLUE)plantuml$(NC) %s\n" "$<"
	@$(PLANTUML) -tsvg -nometadata "$<"

diagrams-clean: ## Remove generated diagram SVGs
	rm -f $(DIAGRAMS_DIR)/*.svg

specs: ## Compile the SRS/SDS/STG skeletons to docs/specs/build/*.pdf (needs Typst)
	@if [ -z "$(TYPST)" ]; then \
		printf "$(RED)Typst not found.$(NC) Install it: brew install typst (or see https://typst.app).\n"; \
		exit 1; \
	fi
	@mkdir -p docs/specs/build
	@for src in $(SPECS_SRC); do \
		out="docs/specs/build/$$(basename "$${src%.typ}").pdf"; \
		printf "$(BLUE)typst compile$(NC) %s\n" "$$src"; \
		$(TYPST) compile --root docs/specs "$$src" "$$out" || exit 1; \
	done
	@printf "$(GREEN)Built %s spec PDF(s) in docs/specs/build$(NC)\n" "$(words $(SPECS_SRC))"

# =============================================================================
# Media hygiene (strip GPS/device metadata before committing photos/video)
# =============================================================================
sanitize-media: ## Strip GPS/device/metadata (and video audio/data tracks) from docs/assets media
	@if [ -z "$(EXIFTOOL)" ]; then \
		printf "$(RED)exiftool not found.$(NC) Install it: brew install exiftool.\n"; exit 1; \
	fi
	@if [ -n "$(strip $(ASSET_IMAGES))" ]; then \
		printf "$(BLUE)Stripping image metadata (keeping Orientation)...$(NC)\n"; \
		$(EXIFTOOL) -all= -tagsFromFile @ -Orientation -overwrite_original $(ASSET_IMAGES) >/dev/null; \
		printf "  images: %s\n" "$(words $(ASSET_IMAGES))"; \
	fi
	@if [ -n "$(strip $(ASSET_VIDEOS))" ]; then \
		if [ -z "$(FFMPEG)" ]; then printf "$(RED)ffmpeg not found (needed for video).$(NC) brew install ffmpeg.\n"; exit 1; fi; \
		for v in $(ASSET_VIDEOS); do \
			printf "$(BLUE)Stripping video metadata/audio/data tracks: %s$(NC)\n" "$$v"; \
			tmp="$${v%.*}.__sanitizing__.$${v##*.}"; \
			$(FFMPEG) -nostdin -loglevel error -i "$$v" -map 0:v:0 -map_metadata -1 \
				-map_metadata:s:v:0 -1 -c:v copy -an -movflags +faststart -y "$$tmp" && \
			$(EXIFTOOL) -all= -overwrite_original "$$tmp" >/dev/null 2>&1 && \
			mv "$$tmp" "$$v"; \
		done; \
	fi
	@printf "$(GREEN)Media sanitized.$(NC) Verify with 'make verify-media'.\n"

verify-media: ## Read-only release gate: FAIL if committed media still carries GPS/location/owner/serial metadata (or video audio)
	@if [ -z "$(EXIFTOOL)" ]; then \
		printf "$(RED)exiftool not found.$(NC) Install it: brew install exiftool.\n"; exit 1; \
	fi
	@fail=0; \
	pat='GPS|Location|Serial|Owner'; \
	for f in $(ASSET_IMAGES) $(ASSET_VIDEOS); do \
		[ -f "$$f" ] || continue; \
		hits=$$($(EXIFTOOL) -s -G "$$f" 2>/dev/null | grep -Ei "$$pat" || true); \
		if [ -n "$$hits" ]; then \
			printf "$(RED)FAIL: sensitive metadata in %s$(NC)\n" "$$f"; \
			printf "%s\n" "$$hits"; fail=1; \
		fi; \
	done; \
	ffprobe=$$(command -v ffprobe 2>/dev/null); \
	if [ -n "$(strip $(ASSET_VIDEOS))" ] && [ -z "$$ffprobe" ]; then \
		printf "$(RED)FAIL: video assets are present but ffprobe is not installed; the audio/data-track check cannot run.$(NC) Install ffmpeg.\n"; \
		exit 1; \
	fi; \
	if [ -n "$$ffprobe" ]; then \
		for v in $(ASSET_VIDEOS); do \
			[ -f "$$v" ] || continue; \
			astreams=$$($$ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$$v" 2>/dev/null); \
			if [ -n "$$astreams" ]; then \
				printf "$(RED)FAIL: %s still contains an audio stream.$(NC)\n" "$$v"; fail=1; \
			fi; \
		done; \
	fi; \
	if [ "$$fail" -ne 0 ]; then \
		printf "$(RED)verify-media: residual sensitive data found - run 'make sanitize-media'.$(NC)\n"; exit 1; \
	fi; \
	printf "$(GREEN)verify-media: clean$(NC) - no GPS/location/owner/serial metadata; no video audio track.\n"

# =============================================================================
# Packaging
# =============================================================================
PACKAGE          := teensy-sos-review.zip
PACKAGE_MANIFEST := SHA256SUMS.txt
PACKAGE_COMMIT   := SOURCE_COMMIT.txt
# Patterns that must NOT appear in the finished archive. The self-check fails on any.
PACKAGE_JUNK := \.DS_Store|__MACOSX|\.claude/|\.idea/|\.iml$$|settings\.local|\.pio/|\.build-host/|\.exe$$|vendor/platformio/|\.tar\.gz$$|\.git/|\.zip$$

package: ## Build the review archive (tracked files + per-file SHA256SUMS.txt) at committed HEAD
	@rm -f $(PACKAGE) $(PACKAGE).sha256 $(PACKAGE_MANIFEST) $(PACKAGE_COMMIT)
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		printf "$(RED)Not a git repository.$(NC) 'make package' archives tracked files via git; run it inside the repo.\n"; \
		exit 1; \
	fi
	@# Fail closed on a dirty tree: the archive reflects committed HEAD, while the
	@# media-hygiene gate (make verify-media) inspects the WORKING TREE. Requiring a
	@# clean tree guarantees the bytes that were verified are the bytes packaged.
	@# Override for a deliberate throwaway snapshot: make ALLOW_DIRTY=1 package
	@if ! git diff-index --quiet HEAD -- 2>/dev/null && [ -z "$(ALLOW_DIRTY)" ]; then \
		printf "$(RED)Working tree has uncommitted changes.$(NC) 'make package' archives committed HEAD,\n"; \
		printf "so the packaged bytes could differ from what 'make verify-media' checked. Commit first,\n"; \
		printf "or override deliberately with: make ALLOW_DIRTY=1 package\n"; \
		exit 1; \
	fi
	@# Per-file manifest, hashed from the COMMITTED HEAD blobs (never the working tree), so it
	@# always matches the archived content even if the working tree is dirty. Embedded IN the
	@# archive so the whole-zip checksum also covers it. SOURCE_COMMIT.txt records the commit
	@# so recipients can identify the source revision without a .git database in the archive.
	@# Exclude any export-ignored paths so the manifest matches what
	@# `git archive` actually places in the zip; otherwise `shasum -c` fails on absent files.
	@git ls-tree -r --name-only HEAD | sort \
		| git check-attr --stdin export-ignore \
		| sed -n 's/: export-ignore: unspecified$$//p' | while IFS= read -r f; do \
		printf '%s  %s\n' "$$(git cat-file blob "HEAD:$$f" | shasum -a 256 | cut -d' ' -f1)" "$$f"; \
	done > $(PACKAGE_MANIFEST)
	@git rev-parse HEAD > $(PACKAGE_COMMIT)
	git archive --format=zip --add-file=$(PACKAGE_MANIFEST) --add-file=$(PACKAGE_COMMIT) -o $(PACKAGE) HEAD
	@rm -f $(PACKAGE_MANIFEST) $(PACKAGE_COMMIT)
	@printf "$(GREEN)Built %s$(NC) (tracked files + $(PACKAGE_MANIFEST) + $(PACKAGE_COMMIT)) - %s files\n" "$(PACKAGE)" "$$(unzip -Z1 $(PACKAGE) | wc -l | tr -d ' ')"
	@if unzip -Z1 $(PACKAGE) | grep -qE '$(PACKAGE_JUNK)'; then \
		printf "$(RED)FAIL: junk/private artifacts in the archive:$(NC)\n"; \
		unzip -Z1 $(PACKAGE) | grep -E '$(PACKAGE_JUNK)'; \
		rm -f $(PACKAGE); exit 1; \
	elif ! unzip -Z1 $(PACKAGE) | grep -qx 'LICENSE'; then \
		printf "$(RED)FAIL: LICENSE is missing from the archive.$(NC)\n"; \
		rm -f $(PACKAGE); exit 1; \
	elif ! unzip -Z1 $(PACKAGE) | grep -qx '$(PACKAGE_MANIFEST)'; then \
		printf "$(RED)FAIL: $(PACKAGE_MANIFEST) is missing from the archive.$(NC)\n"; \
		rm -f $(PACKAGE); exit 1; \
	elif ! unzip -Z1 $(PACKAGE) | grep -qx '$(PACKAGE_COMMIT)'; then \
		printf "$(RED)FAIL: $(PACKAGE_COMMIT) is missing from the archive.$(NC)\n"; \
		rm -f $(PACKAGE); exit 1; \
	else \
		printf "  clean: source, docs, sanitized media + $(PACKAGE_MANIFEST) + $(PACKAGE_COMMIT); LICENSE present\n"; \
	fi
	@# Whole-zip checksum sidecar, delivered ALONGSIDE the zip (a package cannot contain its
	@# own checksum). Two-level integrity: this proves the zip; SHA256SUMS.txt proves each file.
	@rev="$$(git rev-parse HEAD 2>/dev/null)"; \
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$(PACKAGE)" > "$(PACKAGE).sha256"; \
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$(PACKAGE)" > "$(PACKAGE).sha256"; \
	else printf "$(YELLOW)  note: no sha256sum/shasum found; skipped checksum sidecar.$(NC)\n"; fi; \
	if [ -f "$(PACKAGE).sha256" ]; then \
		printf "  commit: %s\n" "$$rev"; \
		printf "  sha256: %s (whole zip)\n" "$$(cut -d' ' -f1 "$(PACKAGE).sha256")"; \
		printf "  verify: 'shasum -a 256 -c $(PACKAGE).sha256' (the zip), then after unzip 'shasum -a 256 -c $(PACKAGE_MANIFEST)' (every file).\n"; \
	fi

# =============================================================================
# Tooling
# =============================================================================
check-tools: ## Report availability of the toolchain
	@printf "Platform      : %b (host-test exe suffix '%s')\n" "$(HOST_OS)" "$(EXE)"
	@printf "PlatformIO    : %b\n" "$(if $(PIO),$(PIO),$(RED)not found$(NC) - pipx install platformio)"
	@printf "arduino-cli   : %b\n" "$(if $(ARDUINO_CLI),$(ARDUINO_CLI),$(RED)not found$(NC) - brew install arduino-cli; only for 'make arduino-*')"
	@printf "C++ (host)    : %b (%s)\n" "$(shell command -v $(CXX) 2>/dev/null || echo '$(RED)not found$(NC)')" "$(CXX)"
	@printf "teensy_loader : %b\n" "$(if $(TEENSY_LOADER),$(TEENSY_LOADER),$(RED)not found$(NC) - only needed for 'make flash' (air-gap path))"
	@printf "Debugger      : %b\n" "$(shell command -v $(DEBUGGER) 2>/dev/null || echo '$(RED)not found$(NC) - $(DEBUGGER); only for make debug-host, see DEBUGGING.md')"
	@printf "PlantUML      : %b\n" "$(if $(PLANTUML),$(PLANTUML),$(RED)not found$(NC) - brew install plantuml or set PLANTUML_JAR; only for 'make diagrams')"
	@printf "Typst         : %b\n" "$(if $(TYPST),$(TYPST),$(RED)not found$(NC) - brew install typst; only for 'make specs')"
	@printf "exiftool      : %b\n" "$(if $(EXIFTOOL),$(EXIFTOOL),$(RED)not found$(NC) - brew install exiftool; only for 'make sanitize-media')"
	@printf "ffmpeg        : %b\n" "$(if $(FFMPEG),$(FFMPEG),$(RED)not found$(NC) - brew install ffmpeg; only for 'make sanitize-media' video)"

check-pio:
	@if [ -z "$(PIO)" ]; then \
		printf "$(RED)PlatformIO not found.$(NC) Install it: pipx install platformio (or brew install platformio).\n"; \
		exit 1; \
	fi

# On Windows, PlatformIO unpacks packages via os.path.relpath, which raises
# "Paths don't have the same drive" when the project-local core dir and Windows
# TEMP live on different drives - e.g. a checkout on a mapped/shared drive (W:)
# while TEMP is on C:. This guard warns loudly before any pio package operation;
# it never blocks. It is inert on macOS/Linux and on a same-drive Windows checkout.
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
