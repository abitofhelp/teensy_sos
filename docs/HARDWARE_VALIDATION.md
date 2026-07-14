# Hardware validation record

End-to-end proof that the `teensy_sos` process works on real hardware: clean-room
firmware, flashed to a physical Teensy 4.1, running the correct SOS Morse pattern on
an RGB LED. This is the evidence the demo is real — build → transfer → flash → run —
not a simulation. **Both command-line frontends** (PlatformIO CLI and Arduino CLI)
were validated on the same board, compiling the same canonical library.

## Build frontends validated

Both frontends compile the same canonical library (`lib/TeensySos/`) to the same
reported code size (`FLASH code:9384`).

| Frontend | Build | Upload | Physical execution (SOS on the RGB LED) |
|---|---|---|---|
| **PlatformIO CLI** | ✅ PASS | ✅ PASS | ✅ PASS |
| **Arduino CLI** (GNU C++20) | ✅ PASS | ✅ PASS | ✅ PASS |
| **Arduino IDE** | ⏳ not tested | ⏳ not tested | ⏳ not tested (planned, separate slice) |

## Environment

| Item | Value |
|---|---|
| Board | Teensy 4.1 (IMXRT1062, 600 MHz) |
| Host | macOS (Apple Silicon), tools via Homebrew |
| PlatformIO platform | `platformio/teensy@5.2.0` (pinned) |
| PlatformIO toolchain | `toolchain-gccarmnoneeabi-teensy@1.150201.0` (GCC 15.2.1) |
| PlatformIO framework | `framework-arduinoteensy@1.162.0` |
| Arduino CLI | `arduino-cli` 1.5.1 |
| Arduino Teensy core | `teensy:avr` 1.62.0 (FQBN `teensy:avr:teensy41`), Arm GCC 15.2.1, GNU C++20 |
| LED | 4-lead common-cathode RGB, R→18 / G→14 / B→15, common→GND |

## Build (`make build`)

PlatformIO cross-compile succeeded. Firmware footprint is tiny:

```
FLASH: code:9384, data:4040, headers:9100   free for files:8103940
RAM1:  variables:4992, code:6832            free for local variables:486528
RAM2:  variables:12416                      free for malloc/new:511872
[SUCCESS] Took 2.63 seconds
```

Note: on an Alire-configured host the Makefile's `PIO_ENV_SANITIZE` strips
`CPATH`/`*_INCLUDE_PATH`/`LIBRARY_PATH` from the firmware build so host SDK headers
cannot leak into the ARM cross-compile. This sanitizes the known GCC include/library
environment variables; it does not make the whole build hermetic (`PATH`, PlatformIO
Core, and package resolution still matter).

## Flash — air-gap path (`make flash`)

The prebuilt `.hex` was flashed with the standalone loader, **no PlatformIO and no
network** — the exact enclave workflow:

```
teensy_loader_cli --mcu=TEENSY41 -w -v firmware.hex
Read "firmware.hex": 22528 bytes, 0.3% usage
Found HalfKay Bootloader
Programming...................
Booting
```

The `.hex` is 22,528 bytes of Intel HEX (ASCII) — inspectable, guard-friendly.

## Run — observed behavior

Repeating SOS, correct color-per-letter, correct Morse timing:

```
rrr   g  g  g   bbb    (pause ~1.4 s, repeat)
S(red dots) · O(green dashes) · S(blue dots)
```

- ✅ Sequence and pattern correct (3 dots / 3 dashes / 3 dots).
- ✅ Color mapping correct (R→18, G→14, B→15).
- ✅ Gaps fully dark (confirms common-cathode polarity, `kCommonAnode = false`).

## Arduino CLI frontend (`make arduino-build` / `make arduino-upload`)

The **same canonical library** was compiled and flashed through the Arduino CLI
(`arduino-cli` 1.5.1, `teensy:avr` 1.62.0), confirming a second command-line
frontend works on the same board:

- **Build PASS.** `arduino-cli compile --fqbn teensy:avr:teensy41` with the GNU
  C++20 flag set (Arduino/Teensyduino defaults to C++17) produced firmware of the
  same size — `FLASH: code:9384` — from the repository-local `lib/TeensySos` library.
- **Upload PASS.** Flashed to the connected Teensy 4.1 from the **absolute**
  `--input-dir`; a relative input dir had previously caused the Teensy loader to
  report it could not read the compiled sketch, so absolute paths are used.
- **Physical execution PASS.** After reboot the board ran the canonical pattern —
  red **S** · green **O** · blue **S**, dark word gap, repeat — indistinguishable
  from the PlatformIO build (as expected: same library, same `FLASH code:9384`).

**Arduino IDE:** not tested — planned as a separate slice and validated separately.

## Bring-up notes (lessons, for the next board)

- **Dark / intermittently-dark LED root cause was mechanical, never firmware.** Two
  variants of the same class of fault were seen: (1) the three signal jumpers were in
  the correct breadboard columns but not seated on the Teensy 18/14/15 pins — an open
  anode path; and (2) intermittent darkness from **loose, unsoldered mechanical
  contacts** on the breadboard (a channel dropping out as the wiring was nudged). In
  both cases the ground return (LED common → ground rail → a Teensy `GND` pin) was
  fine, and the firmware, color mapping, and polarity were never the problem — the same
  image ran correctly once the contacts were reseated. A soldered harness would remove
  this class of fault entirely.
- **Brightness balance:** at 440 Ω on a 3.3 V rail, red is bright but green/blue are
  starved (their Vf ≈ 3.0–3.3 V leaves almost no headroom). Green also *looks* brighter
  than red/blue at equal current because human vision peaks at green — so balancing
  perceived brightness means **more** resistance on green, **less** on blue. See
  `HARDWARE.md` for the tuned values. (Real products would balance via per-channel PWM
  or a 5 V transistor driver; the demo keeps plain resistors for clarity.)
- The Teensy's "N blinks + pause" appears on its **separate red bootloader/status LED**,
  not the orange pin-13 user LED — it is the board's own status indicator, not this
  firmware (the SOS program drives neither on-board LED).

## What this proves for the reusable process

The full pipeline — **build outside → transfer only the `.hex` → flash inside with a
single standalone tool → correct behavior** — is demonstrated with zero proprietary
content, and through **both** command-line frontends (PlatformIO CLI and Arduino CLI)
compiling one canonical library. The same process carries forward to the STM32
pre-production reference board.
