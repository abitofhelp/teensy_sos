# Building & flashing `teensy_sos`

This project demonstrates a **reusable, cross-platform, restricted-network build
process** for embedded firmware. The domain (an SOS blinker) is trivial on
purpose; the value is the build/transfer/flash workflow around it, which carries
over to real firmware and to the STM32 pre-production path, with a board-specific
package set and its own validation.

The project supports **two command-line frontends** — **PlatformIO CLI** (the
default) and the **Arduino CLI** — that compile the *same* canonical library
(`lib/TeensySos/`) and produce identical firmware. The four network/transfer paths
below (A–D) describe how PlatformIO obtains its toolchain under increasing network
restriction, from the normal open-network flow to the fully air-gapped one; the
Arduino CLI frontend is documented in its own section after them. **Arduino IDE
support is planned and not yet validated.**

## Modular build system

The `Makefile` holds only common logic (host detection, colors, the `BUILDER`
selector, and the generic verb aliases). Each build tool is a self-contained
**fragment** under `mk/` that is auto-discovered and included:

- `mk/arduino.mk`, `mk/platformio.mk` — one per builder; each realizes the same
  **target contract** (below).
- `mk/boards/teensy41.mk` — board-owned, build-tool-agnostic concerns (the
  air-gap `flash` target), consuming the `.hex` from whichever builder ran.

### The builder contract

A builder fragment `mk/<tool>.mk` is a drop-in: define these and the root wires it
in with no edits to the root or the other fragments. To add a build tool (e.g. an
STM32 CLI later), copy an existing fragment and provide:

| Obligation | Purpose |
|---|---|
| `build-<tool>` | Compile the firmware. Should depend on `check-<tool>`. |
| `upload-<tool>` | Build, then flash a connected board. |
| `monitor-<tool>` | Open the serial monitor. Guard the tool first (`$(call need,<TOOL>)`). |
| `clean-<tool>` | Remove that builder's build output. |
| `check-<tool>` | Verify the toolchain is present/usable; wired as a `build-<tool>` prerequisite. Give it a `##` help line when it does validation worth running standalone (as `check-arduino` does). |
| `HEX_<tool> := …` | Path to the built `.hex`. The root resolves `HEX ?= $(HEX_$(BUILDER))`, which the board's `flash` consumes. |
| `check-tools::` line | Append one `$(call report,<TOOL>)` so `make check-tools` covers this builder. |

The generic verbs (`build`, `upload`, `monitor`, `clean`) alias to `-$(BUILDER)`;
`clean` and `check-tools` aggregate every present builder automatically. Anything
that has no cross-tool analog (e.g. PlatformIO's offline cache — `pio-prime`,
`pio-bundle`, `build-offline`) stays builder-namespaced and out of the contract.

`BUILDER` selects which fragment the generic verbs bind to — `make build` runs
`build-$(BUILDER)`. It defaults to `platformio` when present, otherwise the first
builder found, so the same root works on the full tree and on a subset with a
fragment removed (`make BUILDER=arduino build` overrides it). Adding a build tool
(e.g. an STM32 CLI later) is dropping in `mk/stm32.mk` that realizes the same
contract — no edits to the root or the other fragments. See the
[build-system diagram](diagrams/build_system.svg).

## Host unit tests (independent of all build paths — no board, no toolchain)

Only a C++20 compiler is needed:

```sh
make test          # Core 34 · Morse 15 · SosController 16 = 65 checks, 0 failures
```

These build the domain/application layers on the host with fake adapters. No
Teensy toolchain, no network.

## Path A — Normal, open network (how PlatformIO is meant to be used)

On a machine with unrestricted internet:

```sh
make check-tools   # confirm PlatformIO + a C++ compiler are present
make build         # PlatformIO downloads the pinned platform/toolchain, compiles
make upload        # build + flash a connected Teensy over USB
```

First `make build` downloads `platformio/teensy@5.2.0` (the pinned platform), the
`arm-none-eabi` GCC toolchain, and the Arduino framework, then compiles. This is
the baseline "normal development" flow.

## Path B — Proxy present, with credentials / CA (corporate, authenticated)

When a proxy is reachable but requires authentication and does TLS inspection,
point PlatformIO at the proxy and the corporate CA, then build normally:

```sh
export HTTPS_PROXY="http://user:pass@proxy.example:8080"
export HTTP_PROXY="$HTTPS_PROXY"
export REQUESTS_CA_BUNDLE=/path/to/corporate-ca.pem
export SSL_CERT_FILE="$REQUESTS_CA_BUNDLE"
make build
```

The Makefile preserves these variables through the firmware build (the CPATH
sanitizer uses a targeted `env -u`, never `env -i`, precisely so proxy/CA vars
survive — see "Environment hygiene" below).

## Path C — Air-gapped / proxy blocks downloads (offline cache bundle)

When the machine cannot reach the PlatformIO registry at all, pre-build an
OS/arch-specific package cache on a **connected** machine of the **same OS/arch**,
transfer the bundle, and build from it offline.

**On the connected machine (same OS/arch as the target):**

```sh
make pio-prime     # populate vendor/platformio and prove it builds
make pio-bundle    # -> teensy-pio-cache-<OS>-<arch>.tar.gz
```

**Transfer** `teensy-pio-cache-<OS>-<arch>.tar.gz` to the restricted machine, then
**unpack it into `vendor/`** (this is the critical step — the archive's top-level
entry is `platformio/`, so it must land at `vendor/platformio/`):

```sh
mkdir -p vendor
tar -xzf teensy-pio-cache-<OS>-<arch>.tar.gz -C vendor/
# result: vendor/platformio/  (NOT ./platformio/)
make build-offline
```

`make build-offline` routes PlatformIO at the project-local `vendor/platformio`
core and does not intentionally install or update. Bundles are **OS/arch-specific**
— prime a Windows bundle on Windows, a Linux bundle on Linux; never cross them.

> **Security note.** Using an offline bundle is an *approval decision*, not a
> bypass: the bundle is built where the system can reach the internet, then
> **securely transferred** for internal use. The bundle contains only the reviewed,
> resolved PlatformIO packages — the platform is pinned, and because its transitive
> dependencies use version ranges, the exact resolved versions are captured and verified
> against `docs/PACKAGE_INVENTORY.md`.

## Path D — Cross-domain: transfer only the `.hex`, flash inside the enclave

For a DoD/air-gapped enclave, the smallest-surface path is to build the firmware
**outside** the enclave and carry only the compiled artifact across the software
bridge:

1. Build on a connected machine (Path A/B/C) → `.pio/build/teensy41/firmware.hex`.
2. `firmware.hex` is **Intel HEX**: a small (~tens of KB) file that is an **ASCII
   encoding of executable machine code** — easier for a cross-domain guard to validate
   and hash than an opaque binary, though it remains executable firmware.
3. Transfer only that `.hex` across the software bridge into the enclave.
4. Inside the enclave, flash it with the standalone loader — **no PlatformIO, no
   network**:
   ```sh
   make flash HEX=/path/to/firmware.hex
   ```
   `make flash` uses `teensy_loader_cli`; the enclave needs only that one tool (or
   the Teensy Loader GUI). This path can obviate the offline bundle entirely for
   the enclave, since nothing there needs to build.

## Arduino CLI — second command-line frontend

The Arduino CLI compiles the **same canonical library** (`lib/TeensySos/`) as
PlatformIO, through the thin sketch `arduino/teensy_sos/teensy_sos.ino`. Both
frontends report the same code size (`FLASH code:9384`) and run identically on
hardware. **Arduino IDE support is
a separate, not-yet-validated slice** — the targets below use the **Arduino CLI only**.

### Prerequisites

- **arduino-cli** (validated: 1.5.1) — `brew install arduino-cli`.
- **Teensy core** (validated: `teensy:avr` 1.62.0). If `make check-arduino` reports
  it missing, add PJRC's package index and install the core:
  ```sh
  arduino-cli config add board_manager.additional_urls \
    https://www.pjrc.com/teensy/package_teensy_index.json
  arduino-cli core update-index
  arduino-cli core install teensy:avr@1.62.0
  ```

### Build and upload

```sh
make check-arduino    # verify arduino-cli, the Teensy core, and the teensy41 board
make build-arduino    # compile with GNU C++20 against the canonical library
make upload-arduino   # build + flash the connected Teensy (press Program if prompted)
make compare-builds   # build BOTH frontends (PlatformIO + Arduino CLI) and compare sizes
```

### Details that matter

- **FQBN:** `teensy:avr:teensy41`.
- **GNU C++20 is required.** Arduino/Teensyduino defaults to GNU C++17, so
  `build-arduino` **replaces** the core's `build.flags.cpp` with the validated set:
  ```
  -std=gnu++20 -fno-exceptions -fpermissive -fno-rtti -fno-threadsafe-statics
  -felide-constructors -Wno-error=narrowing -Wno-psabi -Wno-maybe-uninitialized
  ```
- **Absolute build directory.** The compile writes to an absolute `--output-dir`,
  and upload reads from the matching absolute `--input-dir`. A *relative* input dir
  makes the Teensy loader report that it cannot read the compiled sketch — so the
  Makefile always uses absolute paths.
- **Dynamic port detection.** The Makefile finds the Teensy port from
  `arduino-cli board list` (the row advertising `teensy:avr:teensy41`); it never
  hardcodes a port, because the HID address (e.g. `usb:100000`) is machine- and
  moment-specific. Override it with `make upload-arduino ARDUINO_PORT=...`.
- **Program button.** As with any Teensy upload, press the on-board Program button
  if the loader asks for it.
- **Repository-local library.** The build passes `--library lib/TeensySos`, so it
  uses the in-repo canonical library — nothing is copied into a global Arduino
  sketchbook, and no local package directory is added to version control.

### Standalone `.hex` / Teensy Loader fallback

The Arduino CLI build emits an Intel HEX image under the absolute output directory
(`arduino/teensy_sos/build/teensy_sos.ino.hex`). Like the PlatformIO `.hex`, it can
be flashed with the standalone loader for the cross-domain path (Path D):

```sh
make flash HEX=arduino/teensy_sos/build/teensy_sos.ino.hex
```

## Environment hygiene (why the Makefile strips some variables)

GCC-family compilers — including the Teensy `arm-none-eabi` cross-compiler — honor
`CPATH`, `C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, `OBJC_INCLUDE_PATH`, and
`LIBRARY_PATH`. Some host setups (e.g. an Alire Ada toolchain) export
`CPATH=$SDKROOT/usr/include`, which leaks host SDK headers into the ARM/newlib
firmware build and fails the compile (`__sbuf`/`__sFILE` redefined).

The firmware targets therefore run PlatformIO under a **targeted** sanitizer,
`env -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u OBJC_INCLUDE_PATH -u
LIBRARY_PATH`. It is deliberately *not* `env -i`: `PATH`, `SDKROOT`, proxy/CA
variables, and `PLATFORMIO_CORE_DIR` (the offline-cache routing) are all
preserved. Host unit tests (`make test`) are **not** sanitized — a host SDK on
`CPATH` is harmless, even wanted, for a native compile.

## Windows note — keep the checkout on the same drive as `TEMP`

On Windows, PlatformIO can fail package unpack with *"Paths don't have the same
drive"* if the checkout is on a mapped/shared drive (e.g. `W:`) while `TEMP` is on
`C:`. Clone to a local `C:` path. `make check-drive` warns about this before any
package operation (it is inert on macOS/Linux).
