# =============================================================================
# Project Makefile (modular, multi-builder)
# =============================================================================
# Project: teensy_sos (SOS Morse blinker on an RGB LED)
#
# Layout:
#   Makefile              this file - board/tool-agnostic common targets
#                         (help, host tests, docs, media, package, check-tools)
#                         plus build-tool selection.
#   mk/boards/<board>.mk  board-specific: air-gap flashing (teensy_loader_cli).
#   mk/<builder>.mk       one build tool each: build/upload/monitor + extras.
#                         Present today: platformio, arduino.
#
# Pick the build tool with BUILDER=<name> (default: platformio when present,
# else the first available). A real project usually ships ONE builder; this
# starter ships both to demonstrate frontend equivalence. Adding a build tool
# is a drop-in: a new mk/<builder>.mk implementing build/upload - no edits here.
#
# Every present fragment self-registers with the aggregate targets (clean::,
# check-tools::), so those cover exactly what the tree ships.
#
# Host tests need only a C++20 compiler - no Teensy toolchain, no build tool.
# =============================================================================

PROJECT_NAME := teensy_sos
CANON_LIB    := lib/TeensySos/src

# help is the default goal. The first target in the file is check-tools:: (defined
# before the fragment includes), so set the default goal explicitly.
.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
BOLD   := \033[1m
NC     := \033[0m

# -----------------------------------------------------------------------------
# Host platform detection. On Windows - including MSYS2/mingw64 shells - the OS
# environment variable is Windows_NT; elsewhere we fall back to uname. This
# drives the host-test executable suffix and the default host compiler.
# -----------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
  HOST_OS := Windows
  EXE     := .exe
else
  HOST_OS := $(shell uname -s)
  EXE     :=
endif
ARCH := $(shell uname -m 2>/dev/null || echo unknown)

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

# The canonical headers live in $(CANON_LIB), shared by every builder and by the
# host tests, which include them straight from there - no Teensy toolchain.
HOST_CXXFLAGS := -std=c++20 -Wall -Wextra -I$(CANON_LIB)
HOST_BUILD    := .build-host

# Host debugging (LOCAL development only). `make debug-host` builds one host suite
# with debugger-friendly flags and drops into the platform debugger. This debugs
# the DOMAIN/APPLICATION logic on the host - NOT firmware-on-the-chip (the Teensy
# 4.1 has no on-board probe; see DEBUGGING.md). SUITE=core|morse|sos (default sos).
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
DEBUGGER_NAME := $(DEBUGGER)
DEBUGGER_HINT := see DEBUGGING.md (macOS: xcode-select --install; Linux: install gdb; MSYS2: pacman -S mingw-w64-ucrt-x86_64-gdb); only for 'make debug-host'.

# -----------------------------------------------------------------------------
# Documentation + media tools (used by common targets and reported by check-tools)
# -----------------------------------------------------------------------------
DIAGRAMS_DIR := docs/diagrams
PUML         := $(wildcard $(DIAGRAMS_DIR)/*.puml)
SVG          := $(PUML:.puml=.svg)
SPECS_SRC    := $(wildcard docs/specs/*.typ)
ASSET_IMAGES := $(wildcard docs/assets/images/*.jpeg docs/assets/images/*.jpg docs/assets/images/*.png)
ASSET_VIDEOS := $(wildcard docs/assets/videos/*.mov docs/assets/videos/*.mp4)

PLANTUML_JAR ?=
ifneq ($(shell command -v plantuml 2>/dev/null),)
  PLANTUML := plantuml
else ifneq ($(PLANTUML_JAR),)
  PLANTUML := java -jar $(PLANTUML_JAR)
else
  PLANTUML :=
endif
PLANTUML_NAME := PlantUML
PLANTUML_HINT := brew install plantuml or set PLANTUML_JAR=<path>; only for 'make diagrams'.
TYPST         := $(shell command -v typst 2>/dev/null)
TYPST_NAME    := Typst
TYPST_HINT    := brew install typst (or see https://typst.app); only for 'make specs'.
EXIFTOOL      := $(shell command -v exiftool 2>/dev/null)
EXIFTOOL_NAME := exiftool
EXIFTOOL_HINT := brew install exiftool; only for 'make sanitize-media'.
FFMPEG        := $(shell command -v ffmpeg 2>/dev/null)
FFMPEG_NAME   := ffmpeg
FFMPEG_HINT   := brew install ffmpeg; only for 'make sanitize-media' video.

# -----------------------------------------------------------------------------
# Helpers (DRY the repeated tool guards and error exits)
#   $(call need,VAR)   fail a recipe if $(VAR) is empty, printing "<NAME> not
#                      found. <HINT>". Each guarded tool defines VAR_NAME/VAR_HINT.
#   $(call die,text)   print a red error and fail (text must not contain commas).
#   $(call report,VAR) one check-tools line: the path, or red "not found - HINT".
# -----------------------------------------------------------------------------
need   = @[ -n "$($(1))" ] || { printf "$(RED)%s not found.$(NC) %b\n" "$($(1)_NAME)" "$($(1)_HINT)" >&2; exit 1; }
die    = { printf "$(RED)%b$(NC)\n" "$(1)" >&2; exit 1; }
report = @printf "%-13s : %b\n" "$($(1)_NAME)" "$(if $($(1)),$($(1)),$(RED)not found$(NC) - $($(1)_HINT))"

# -----------------------------------------------------------------------------
# Build-tool selection. Builders are the mk/*.mk fragments present in the tree.
# Default to platformio when it ships, else the first available builder - so the
# SAME root Makefile works on a full tree and on an arduino-only delivery subset
# with no edits. An explicit but unavailable BUILDER fails loudly.
# -----------------------------------------------------------------------------
BUILDERS := $(sort $(patsubst mk/%.mk,%,$(wildcard mk/*.mk)))
ifeq ($(BUILDERS),)
  $(error No build-tool fragments found in mk/. Add mk/<builder>.mk)
endif
BUILDER ?= $(if $(filter platformio,$(BUILDERS)),platformio,$(firstword $(BUILDERS)))
ifeq ($(filter $(BUILDER),$(BUILDERS)),)
  $(error BUILDER='$(BUILDER)' is not available. Present builders: $(BUILDERS). Use BUILDER=<one of them>)
endif

# Common check-tools lines are defined here (before the includes) so they print
# first; each board/builder fragment appends its own tool line via `check-tools::`.
.PHONY: check-tools
check-tools:: ## Report availability of the toolchain (each fragment adds its tools)
	@printf "%-13s : %b (host-test exe suffix '%s')\n" "Platform" "$(HOST_OS)/$(ARCH)" "$(EXE)"
	@printf "%-13s : %b (%s)\n" "C++ (host)" "$(shell command -v $(CXX) 2>/dev/null || printf '$(RED)not found$(NC)')" "$(CXX)"
	@printf "%-13s : %b\n" "$(DEBUGGER_NAME)" "$(shell command -v $(DEBUGGER) 2>/dev/null || printf '$(RED)not found$(NC)') - only for 'make debug-host'"
	$(call report,PLANTUML)
	$(call report,TYPST)
	$(call report,EXIFTOOL)
	$(call report,FFMPEG)

# Include every present board + builder fragment. All contribute to check-tools::;
# each builder provides its own build-<builder>/upload-<builder>/monitor-<builder>/
# clean-<builder> targets and a HEX_<builder> path. The generic verbs below alias
# to the selected $(BUILDER).
include $(wildcard mk/boards/*.mk)
include $(wildcard mk/*.mk)

# =============================================================================
# Firmware verbs - resolve to the selected BUILDER (implemented in mk/<builder>.mk)
# =============================================================================
HEX ?= $(HEX_$(BUILDER))
.PHONY: build upload burn monitor
build:   build-$(BUILDER)   ## Build firmware with the selected build tool
upload:  upload-$(BUILDER)  ## Build + flash with the selected build tool
burn:    upload             ## Alias for upload (build + flash)
monitor: monitor-$(BUILDER) ## Open the serial monitor with the selected build tool

# =============================================================================
# Default / help
# =============================================================================
.PHONY: all help
all: help

help: ## Display this help message
	@printf "$(BOLD)$(PROJECT_NAME) - SOS Morse blinker on an RGB LED$(NC)\n\n"
	@printf "$(BOLD)Targets:$(NC)\n"
	@grep -hE '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN{FS=":.*##"} {printf "  $(CYAN)%-16s$(NC) %s\n", $$1, $$2}'
	@printf "\n$(BOLD)Build tool:$(NC) BUILDER=$(BUILDER)  (available: $(BUILDERS))\n"
	@printf "$(BOLD)Variables:$(NC) CXX=%s   HEX=%s (for 'flash')\n" "$(CXX)" "$(HEX)"

# =============================================================================
# Host tests (no Teensy toolchain required)
# =============================================================================
.PHONY: test test-core test-morse test-sos debug-host
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
	@[ -n "$(DBG_SRC)" ] || $(call die,Unknown SUITE='$(SUITE)'. Use SUITE=core|morse|sos.)
	$(call need,DEBUGGER)
	@printf "$(BLUE)Building %s with debug symbols ($(HOST_DBGFLAGS))...$(NC)\n" "$(DBG_SRC)"
	$(CXX) $(HOST_CXXFLAGS) $(HOST_DBGFLAGS) $(DBG_SRC) -o $(HOST_BUILD)/debug_$(SUITE)$(EXE)
	@printf "$(BLUE)Launching $(DEBUGGER) on $(HOST_BUILD)/debug_$(SUITE)$(EXE)$(NC) (run with 'run'; quit with 'quit').\n"
	@$(DEBUGGER) $(HOST_BUILD)/debug_$(SUITE)$(EXE)

# =============================================================================
# Documentation (PlantUML diagrams + Typst formal docs)
# =============================================================================
.PHONY: docs diagrams clean-diagrams specs
docs: diagrams specs ## Build all documentation (diagrams + spec skeletons)
	@printf "$(GREEN)All documentation built.$(NC)\n"

diagrams: $(SVG) ## Generate SVGs from all docs/diagrams/*.puml

$(DIAGRAMS_DIR)/%.svg: $(DIAGRAMS_DIR)/%.puml
	$(call need,PLANTUML)
	@printf "$(BLUE)plantuml$(NC) %s\n" "$<"
	@$(PLANTUML) -tsvg -nometadata "$<"

clean-diagrams: ## Remove generated diagram SVGs
	rm -f $(DIAGRAMS_DIR)/*.svg

specs: ## Compile the SRS/SDS/STG skeletons to docs/specs/build/*.pdf (needs Typst)
	$(call need,TYPST)
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
.PHONY: sanitize-media verify-media
sanitize-media: ## Strip GPS/device/metadata (and video audio/data tracks) from docs/assets media
	$(call need,EXIFTOOL)
	@if [ -n "$(strip $(ASSET_IMAGES))" ]; then \
		printf "$(BLUE)Stripping image metadata (keeping Orientation)...$(NC)\n"; \
		$(EXIFTOOL) -all= -tagsFromFile @ -Orientation -overwrite_original $(ASSET_IMAGES) >/dev/null; \
		printf "  images: %s\n" "$(words $(ASSET_IMAGES))"; \
	fi
	@if [ -n "$(strip $(ASSET_VIDEOS))" ]; then \
		if [ -z "$(FFMPEG)" ]; then $(call die,ffmpeg not found (needed for video). brew install ffmpeg.); fi; \
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
	$(call need,EXIFTOOL)
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
		$(call die,video assets present but ffprobe is not installed; the audio/data-track check cannot run. Install ffmpeg.); \
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
PACKAGE_JUNK := \.DS_Store|__MACOSX|\.claude/|\.idea/|\.iml$$|settings\.local|\.pio/|\.build-host/|\.exe$$|vendor/platformio/|\.tar\.gz$$|\.git/|\.zip$$

.PHONY: package
package: ## Build the review archive (tracked files + per-file SHA256SUMS.txt) at committed HEAD
	@rm -f $(PACKAGE) $(PACKAGE).sha256 $(PACKAGE_MANIFEST) $(PACKAGE_COMMIT)
	@git rev-parse --is-inside-work-tree >/dev/null 2>&1 || $(call die,Not a git repository. 'make package' archives tracked files via git; run it inside the repo.)
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
	@# Per-file manifest, hashed from the COMMITTED HEAD blobs (never the working tree).
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
# Aggregate clean + rebuild. Each builder fragment provides its own clean-<builder>.
# =============================================================================
.PHONY: clean clean-host rebuild
clean: clean-host $(addprefix clean-,$(BUILDERS)) ## Remove all build artifacts (host + every shipped builder)

clean-host: ## Remove host-test artifacts (.build-host)
	@printf "$(YELLOW)Cleaning host-test artifacts...$(NC)\n"
	rm -rf $(HOST_BUILD)

rebuild: clean build ## Clean, then build with the selected builder

# Reference/equivalence check: build with every shipped builder (they have distinct
# build-<builder> targets, so no recursion or collision). Only defined when 2+
# builders ship. Size/image match is DIAGNOSTIC, not proof of functional equivalence
# (that needs the on-hardware smoke test).
ifneq (,$(and $(filter platformio,$(BUILDERS)),$(filter arduino,$(BUILDERS))))
.PHONY: compare-builds build-all
compare-builds: $(addprefix build-,$(BUILDERS)) ## Build with every shipped builder (diagnostic equivalence check)
	@printf "$(GREEN)Built with: $(BUILDERS).$(NC) Size/image match is diagnostic, not proof of functional equivalence.\n"

build-all: compare-builds ## Alias for compare-builds (back-compat)
endif
