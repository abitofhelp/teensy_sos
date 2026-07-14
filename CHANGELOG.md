# Changelog

All notable changes to `teensy_sos` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) — so entries
below are grouped by the commit type that produced them (`feat`, `fix`, `docs`,
`build`, `test`, …).

## [Unreleased]

_Nothing yet._

## [1.0.0] - 2026-07-14

First public release: a clean-room, proprietary-free starter/reference project that
blinks **SOS** in Morse on an RGB LED (S red · O green · S blue) on a Teensy 4.1,
built on a hexagonal (ports & adapters) / DDD / Clean hybrid architecture in C++20.

### Features

- **Canonical implementation as one shared library** (`lib/TeensySos/`): domain,
  Morse encoder, port concepts, templated `SosController`, and Teensy clock/LED
  adapters. Both command-line frontends compile this single source — no duplication.
- **PlatformIO CLI frontend** (default): `make build` / `make upload`, plus an
  offline package cache (`make pio-prime` / `pio-bundle` / `build-offline`) and
  standalone air-gap `.hex` flashing (`make flash`).
- **Arduino CLI frontend**: `make arduino-build` / `make arduino-upload`, compiling
  the same canonical library with GNU C++20 (`teensy:avr:teensy41`), dynamic port
  detection, and `make build-all` to build both frontends at once.
- **Host unit tests** (`make test`): 79 checks across the core, Morse encoder, and
  controller, runnable with any C++20 compiler — no board, no embedded toolchain.
- **Cross-platform Makefile** targeting macOS, Linux, and Windows/MSYS2, with a
  `CPATH`-sanitized firmware build and four build/transfer paths (open network,
  authenticated proxy, offline-cache bundle, and standalone `.hex` transfer).
- **Reproducible review packaging** (`make package`): a `git archive` of committed
  files plus an embedded per-file `SHA256SUMS.txt` manifest, a recorded source
  commit, and a whole-archive checksum sidecar.
- **Media-hygiene gate** (`make sanitize-media` / `make verify-media`): strips and
  then re-verifies that committed images carry no GPS/owner/serial metadata.

### Documentation

- Architecture guide (the hybrid pattern, one canonical implementation with two thin
  composition roots), build guide, hardware wiring & bench-validation record,
  host/firmware debugging guide, resolved package inventory, SRS/SDS/STG skeletons,
  and rendered PlantUML diagrams.

### Tests

- Host suites for the shared kernel, the Morse encoder, and the `SosController`
  state machine (fake LED + fake clock), covering timing edges and clock rollover.

### Notes

- Validated on macOS (Apple Silicon) with a Teensy 4.1: both CLI frontends build,
  upload, and run the SOS pattern, reporting the same code size (`FLASH code:9384`).
- **Arduino IDE** support is planned for a future release.
- **Windows/MSYS2** is implemented and pending its own validation.

[Unreleased]: https://github.com/abitofhelp/teensy_sos/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/abitofhelp/teensy_sos/releases/tag/v1.0.0
