# teensy_sos

A clean-room **starter / reference project** for Teensy 4.1 firmware, built with a
hexagonal (ports & adapters) / DDD / Clean hybrid architecture in C++20 — and a
**cross-platform, restricted-network build process** for macOS, Linux, and Windows,
online or air-gapped (macOS validated on hardware; Linux and Windows/MSYS2 build
support implemented, their validation pending).

The demo domain is deliberately trivial and **entirely non-proprietary**: blink
**SOS** in Morse on an RGB LED (S in red, O in green, S in blue). The value of the
project is everything *around* that blink — the architecture, the host-testable
core, and the build/transfer/flash workflow — which carries over to real firmware and
to the STM32 pre-production path, with a board-specific package set and its own validation.

## Why this project exists

1. **A shareable demonstration** — nothing here is proprietary, so it can be shared
   freely to demonstrate the hybrid architecture, the cross-platform build, and the
   offline / authenticated-proxy / air-gapped build workflow end to end.
2. **The canonical starter template** — copy it, drop in a real domain, and keep
   the reusable scaffolding (shared kernel, ports/adapters, host tests, Makefile,
   offline-cache targets).

## What it does

Repeating **SOS** in Morse, one color per letter:

| Letter | Morse | Color |
|---|---|---|
| S | `. . .` | Red |
| O | `— — —` | Green |
| S | `. . .` | Blue |

See [`docs/HARDWARE.md`](docs/HARDWARE.md) for the breadboard wiring (common-cathode
RGB LED: R→18, G→14, B→15, common→GND).

## Architecture

Dependencies point inward; the domain knows nothing about hardware.

The layered headers live **once**, canonically, in the `lib/TeensySos/` library;
both command-line frontends (PlatformIO and Arduino CLI) compile that same library
through a thin composition root — there is no duplicated domain/application logic.

| Layer | Namespace | Files (in `lib/TeensySos/src/`) | Depends on |
|---|---|---|---|
| Shared kernel | `sos::core` | `Core.hpp` (Option / Result / FixedQueue) | nothing (`<cstdint>`/`<cstddef>`/`<atomic>`) |
| Domain | `sos::domain` | `Domain.hpp`, `MorseEncoder.hpp` | nothing |
| Application | `sos::app` | `Ports.hpp` (concepts), `SosController.hpp` | domain |
| Infrastructure | `sos::platform` | `TeensyRgbLedAdapter.hpp`, `TeensyClock.hpp` | Arduino |
| Composition roots | — | `src/main.cpp` (PlatformIO) · `arduino/teensy_sos/teensy_sos.ino` (Arduino CLI) | all of the above |

- `SosController` is templated over the `LedPort` / `ClockPort` **C++20 concepts**
  and never mentions Arduino. On the device, `TeensyRgbLedAdapter` + `TeensyClock`
  satisfy the ports; in host tests, a `FakeLed` + `FakeClock` do.
- The Morse expansion (`MorseEncoder`) is pure and exhaustively host-tested, so the
  timing pattern is verified without any hardware.

## Build support

Two command-line frontends compile the **same canonical implementation**
(`lib/TeensySos/`). PlatformIO is the established default; the Arduino CLI is a
supported second frontend. Both compile the same canonical implementation to the
same reported code size (`FLASH code:9384`) and run the SOS pattern identically on
hardware.

| Frontend | Status | Validated on hardware (Teensy 4.1) |
|---|---|---|
| **PlatformIO CLI** | Supported (default) | ✅ build · upload · physical execution |
| **Arduino CLI** | Supported | ✅ build · upload · physical execution |
| **Arduino IDE** | Planned | ⏳ integration & validation pending (separate slice) |

## Prerequisites

- **Host tests only:** any C++20 compiler (`make test`) — no board and no embedded toolchain.
- **On-device runs (hardware):** a Teensy 4.1, a common-cathode RGB LED, three
  current-limiting resistors, and a breadboard — wiring in [`docs/HARDWARE.md`](docs/HARDWARE.md).
- **PlatformIO CLI:** `pipx install platformio` (or `brew install platformio`).
- **Arduino CLI:** `brew install arduino-cli` plus the Teensy core (`teensy:avr`) —
  `make check-arduino` confirms the setup; install steps are in [`docs/BUILD.md`](docs/BUILD.md).

## Quick start

Host tests need no board and no embedded toolchain:

```sh
make test          # host unit tests: 79 checks, 0 failures (no board, no toolchain)
```

**PlatformIO CLI** (default):

```sh
make build         # cross-compile the firmware (PlatformIO)
make upload        # build + flash a connected Teensy
make debug-host    # debug the domain/app logic natively (see docs/DEBUGGING.md)
```

**Arduino CLI** (second frontend, GNU C++20 against the canonical library):

```sh
make check-arduino    # verify arduino-cli, the Teensy core, and the board
make build-arduino    # compile the sketch (FQBN teensy:avr:teensy41)
make upload-arduino   # build + flash the connected Teensy (dynamic port)
```

The generic `make build` / `make upload` target whichever `BUILDER` is selected
(PlatformIO by default; `make BUILDER=arduino build`). Build both frontends and
compare their image sizes with `make compare-builds`. Then watch the RGB LED blink
SOS in red / green / blue.

## Building in restricted networks

Four legitimate paths — normal, authenticated-proxy, offline-cache bundle, and
cross-domain `.hex`-transfer — are documented in **[`docs/BUILD.md`](docs/BUILD.md)**,
which also covers the Arduino CLI workflow. Arduino IDE support is planned and will
be validated separately.

## Documentation

| Doc | What it covers |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | The hybrid DDD/Clean/Hexagonal pattern, with diagrams and the benefits |
| [`docs/BUILD.md`](docs/BUILD.md) | The four build/transfer paths (open / authenticated-proxy / offline bundle / `.hex` transfer) and the Arduino CLI workflow |
| [`docs/PACKAGE_INVENTORY.md`](docs/PACKAGE_INVENTORY.md) | Resolved PlatformIO package set: exact versions + content digests for the pinned platform |
| [`docs/HARDWARE.md`](docs/HARDWARE.md) | Wiring, resistor selection & brightness balancing, reference photos |
| [`docs/HARDWARE_VALIDATION.md`](docs/HARDWARE_VALIDATION.md) | End-to-end bench proof: build → flash → running SOS |
| [`docs/DEBUGGING.md`](docs/DEBUGGING.md) | Host debugging (`make debug-host`) and the firmware debug build (`make build-debug`) |
| `docs/specs/` | SRS / SDS / STG skeletons (Typst → PDF) — starter scaffold |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history (Keep a Changelog + Semantic Versioning + Conventional Commits) |

Build the diagrams and PDFs with `make diagrams` and `make specs`. `make verify-media`
re-checks all committed media for residual GPS/owner/serial metadata as a pre-share gate.

## Layout

```
platformio.ini          Pinned platform (teensy@5.2.0), C++20, no exceptions/RTTI
Makefile                Both CLI frontends + offline cache + air-gap flash + docs + tests
lib/TeensySos/          Canonical implementation (hexagonal layers, header-only) shared by both frontends
src/main.cpp            PlatformIO composition root (thin: wires the library)
arduino/teensy_sos/     Arduino CLI composition root (thin sketch: wires the same library)
test/                   Host unit tests (compile with any C++20 compiler)
docs/                   ARCHITECTURE / BUILD / HARDWARE / HARDWARE_VALIDATION / DEBUGGING
docs/diagrams/          PlantUML sources + rendered SVGs
docs/specs/             Typst formal docs (SRS/SDS/STG skeletons)
docs/assets/            Reference photos (LED wiring & SOS state changes)
```

## AI Assistance & Authorship

This project was authored by Michael Gardner (A Bit of Help, Inc.) with AI coding
assistance used as a tool. All design decisions, review, and accountability rest
with the human author.

## License

BSD-3-Clause. Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc.
