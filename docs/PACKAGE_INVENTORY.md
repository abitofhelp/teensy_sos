# Resolved package inventory — `teensy_sos`

This is the **reviewed package manifest** for `teensy_sos`: the complete set of PlatformIO
packages that a build resolves and uses, with **exact resolved versions** and a **content
digest** for each. It exists so the toolchain can be reviewed and locked rather than
described only as "pinned."

## Why this matters

`platformio.ini` pins the **development platform** to an exact version
(`platformio/teensy@5.2.0`). That platform's manifest, however, declares its transitive
compiler/framework/uploader packages with **compatible-version ranges** (e.g. `~1.162.0`,
`<2`). An exact platform pin is therefore *not* an exact lock of every package. This file
records the **exact versions those ranges resolve to today**, so the reviewed set is
explicit and reproducible.

## Capture environment

These values were captured on one host; they must be regenerated and reviewed for each
target OS and architecture, because the tool and toolchain packages ship OS/architecture-
specific binaries.

| | |
|---|---|
| Capture OS / architecture | macOS (Darwin) `arm64` (Apple Silicon) |
| PlatformIO Core | `6.1.19` |

**PlatformIO Core is separate from the packages below.** `pio` (Core) is installed on the
build machine by an approved method (`pipx install platformio` / `pip`); it is **not** part
of the offline package cache. Its version, source, and integrity must be identified and
approved independently — the version used to capture this inventory is recorded above.

## Resolved set (for `env:teensy41`, platform `teensy @ 5.2.0`)

| Component | Resolved version | Declared spec (range) | Content digest (SHA-256) |
|---|---|---|---|
| `teensy` (platform) | `5.2.0` | `platformio/teensy @ 5.2.0` | `6e218c5fc6403d065f877f0c89423a8a5d8cd7693ff56f6a667daafd36e954a5` |
| `framework-arduinoteensy` | `1.162.0` | `~1.162.0` | `26cdf856f0d15a72a426cd0b394ef2412a61f2f85bbcf83e92387b34dc11cccd` |
| `tool-teensy` | `1.162.0` | `<2` | `d0377c13a336e7b4ee19a6ffec99968d5a776ca5ea723f65f95dc829025957f6` |
| `toolchain-gccarmnoneeabi-teensy` | `1.150201.0` | `~1.150201.0` | `230c3083018793b84e4df137133ee5fb6b8b0480c2443d1a4271d8e2970bde17` |

*(`env:teensy41_debug` uses the same package set; it only adds compiler flags.)*

## Arduino CLI frontend (validated on macOS)

The Arduino CLI is a second command-line frontend that compiles the same canonical
library (`lib/TeensySos/`). Its toolchain is obtained and versioned independently of the
PlatformIO package set above; the following versions were **validated on macOS (Apple
Silicon), on real hardware**:

| Component | Version |
|---|---|
| Arduino CLI | `1.5.1` |
| Teensy core (`teensy:avr`) | `1.62.0` |
| Board FQBN | `teensy:avr:teensy41` |
| Compiler | Arm GCC `15.2.1` |
| Language standard | GNU C++20 (`-std=gnu++20`; Arduino/Teensyduino defaults to C++17) |
| PlatformIO platform (cross-reference) | `platformio/teensy@5.2.0` |

**Not yet validated on Windows.** These exact Arduino CLI / Teensy-core versions are
validated on **macOS only**. Windows (and Windows/MSYS2) validation of the Arduino CLI
frontend — like the PlatformIO offline bundle and the PlatformIO Windows build — must be
performed and recorded separately before it can be claimed.

## How the content digest is computed (reproducible)

Each digest is a SHA-256 roll-up of the package's **file contents** (not install metadata),
computed from the installed package directory:

```sh
# For an installed package directory <dir> (e.g. ~/.platformio/packages/tool-teensy):
( cd <dir> && find . -type f -not -name '.piopm' | LC_ALL=C sort \
    | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1 )
```

The digest excludes PlatformIO's per-install `.piopm` metadata file, so it depends only on
the published package contents for that version. Reproducibility depends on the package
type: `framework-arduinoteensy` is source and its digest is expected to reproduce across
hosts, but `tool-teensy` and `toolchain-gccarmnoneeabi-teensy` contain **OS/architecture-
specific binaries**, so their digests reproduce only on the **same OS and architecture as
the capture environment above**. Regenerate the resolved versions with
`pio pkg list -e teensy41`.

## Relationship to the offline bundle

When Ask 2 (the offline bundle) is used, the transferred artifact is a per-OS/arch archive
(`teensy-pio-cache-<os>-<arch>.tar.gz`) whose **whole-archive SHA-256** is the integrity
anchor for the exact transferred bytes. The versions and content digests above identify the
package *set* independent of that OS/arch packaging, so both can be reviewed together.

> Values captured from a resolution of `platformio/teensy@5.2.0`. Re-run the commands above
> to confirm; if the registry publishes new in-range versions, re-resolving may pick them up
> unless the exact versions in this table are held.
