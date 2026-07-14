# Debugging `teensy_sos`

This project supports two very different kinds of debugging. Pick the one that
matches what you are actually trying to inspect:

| You want to debug… | Use | Needs hardware? |
|---|---|---|
| The **domain / application logic** (Morse program, `SosController` state machine, `Core` types) | **Host debugging** — `make debug-host` | No. Runs on your workstation. |
| The **running firmware on the chip** (breakpoints on the Teensy itself) | **Firmware debug build** — `make build-debug` + an external probe | **Yes** — a Teensy 4.1 has no on-board debugger. |

> **The honest hardware truth.** Unlike many STM32 boards (which carry an on-board
> ST-Link), the **Teensy 4.1 has no on-board debug probe**. You cannot set a live
> breakpoint on the chip over plain USB. Source-level on-chip debugging requires an
> **external SWD/JTAG probe** (e.g. a Segger J-Link) physically wired to the Teensy's
> SWD pads. Without a probe, debug the logic on the host (below) and use serial
> prints (`Serial.print`, viewed with `make monitor`) on the board.

Neither path changes the release build: the canonical `[env:teensy41]` profile in
`platformio.ini` is left untouched. Debugging uses a separate `make debug-host`
host binary and a separate `[env:teensy41_debug]` firmware profile.

---

## 1. Host debugging (recommended — no hardware, always available)

Because the architecture is hexagonal, the domain and application layers build and
run on your workstation with fake adapters (`FakeLed`, `FakeClock`). That means the
interesting logic can be debugged natively, fast, with no board attached.

```sh
make debug-host                 # defaults to the SosController suite
make debug-host SUITE=core      # Core / FixedQueue suite
make debug-host SUITE=morse     # Morse encoder suite
make debug-host SUITE=sos       # SosController suite (default)
```

`debug-host` compiles the chosen suite with debugger-friendly flags
(`-Og -g3 -fno-omit-frame-pointer`) into `.build-host/debug_<suite>` and launches
your platform debugger. The debugger is chosen automatically:

- **macOS** → `lldb`
- **Linux / MSYS2** → `gdb`

Override it if you prefer a different one:

```sh
make debug-host DEBUGGER=gdb
```

### First commands once the debugger opens

The test binary does not take arguments; it runs all checks in `main()`.

**lldb** (macOS):
```
(lldb) b build_sos                 # breakpoint on a function
(lldb) run                         # start the program
(lldb) bt                          # backtrace
(lldb) frame variable              # locals in the current frame
(lldb) c                           # continue
(lldb) quit
```

**gdb** (Linux / MSYS2):
```
(gdb) break build_sos
(gdb) run
(gdb) backtrace
(gdb) info locals
(gdb) continue
(gdb) quit
```

Good breakpoint targets in this project: `sos::domain::build_sos`,
`sos::app::SosController::begin`, `sos::app::SosController::poll`.

---

## 2. Firmware debug build (symbols on the chip)

To produce a symbol-rich firmware image with light, debuggable optimization:

```sh
make build-debug                 # pio run -e teensy41_debug
```

This builds the `[env:teensy41_debug]` profile, which **inherits** everything from
the release `[env:teensy41]` env and adds `-Og -g3 -fno-omit-frame-pointer` plus
`build_type = debug`. The output is `.pio/build/teensy41_debug/firmware.elf`
(with full symbols) and `firmware.hex`.

You can always **inspect** this ELF statically without any probe:

```sh
arm-none-eabi-objdump -d .pio/build/teensy41_debug/firmware.elf | less   # disassembly
arm-none-eabi-nm -S --size-sort .pio/build/teensy41_debug/firmware.elf    # symbol sizes
arm-none-eabi-addr2line -e .pio/build/teensy41_debug/firmware.elf <addr>  # addr -> file:line
```
(The `arm-none-eabi-*` tools ship inside the PlatformIO Teensy toolchain package.)

### Live on-chip debugging (requires an external probe)

To set breakpoints on the running chip you need an SWD/JTAG probe wired to the
Teensy 4.1's SWD pads, and PlatformIO's debug workflow:

```sh
pio debug -e teensy41_debug      # starts a gdb session through the probe
```

`[env:teensy41_debug]` declares `debug_tool = jlink` as the expected probe; change
it to match your hardware if you use a different one. Wiring the SWD pads and
setting up the probe is beyond this starter — consult your probe's documentation
and the PJRC forums. **Without a probe, `pio debug` cannot attach; use host
debugging (section 1) instead.**

---

## Installing a debugger

| OS | Debugger | Install |
|---|---|---|
| **macOS** | lldb | Comes with the Xcode Command Line Tools: `xcode-select --install` |
| **Linux (Debian/Ubuntu)** | gdb | `sudo apt-get install gdb` |
| **Linux (Fedora)** | gdb | `sudo dnf install gdb` |
| **Windows / MSYS2 (UCRT64)** | gdb | `pacman -S mingw-w64-ucrt-x86_64-gdb` |

`make check-tools` reports whether your default debugger is on the `PATH`.

---

## Which build am I running?

| Profile | Flags added | Purpose |
|---|---|---|
| `env:teensy41` (release, default) | none beyond the house C++ standard | The canonical, shippable firmware. **Never** altered for debugging. |
| `env:teensy41_debug` | `-Og -g3 -fno-omit-frame-pointer`, `build_type=debug` | Local debugging only. Bigger, symbol-rich, not for release. |

Ship the release build. Use the debug profile only while investigating a problem.
