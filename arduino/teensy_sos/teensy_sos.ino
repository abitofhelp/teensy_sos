// teensy_sos.ino - Arduino CLI composition root for the SOS Morse RGB-LED demo.
//
// This is a THIN composition root, intentionally identical in structure to the
// PlatformIO root (../../src/main.cpp): it owns the concrete adapters and wires
// them into the templated SosController. It contains NO SOS implementation of
// its own - the behavior lives once, canonically, in the TeensySos library
// (../../lib/TeensySos), which both frontends compile.
//
// Build/upload it with the Arduino CLI via the Makefile:
//   make arduino-build     # compile with GNU C++20 against the canonical library
//   make arduino-upload    # build + flash the connected Teensy 4.1
// The Makefile passes the repository-local library with `--library lib/TeensySos`
// and the required GNU C++20 build flags (Arduino/Teensyduino defaults to C++17).
//
// Wiring (common-CATHODE RGB LED, common lead -> GND, channels active-HIGH):
//   R -> pin 18   G -> pin 14   B -> pin 15   (each leg resistor-protected)
// Output: S (red) ... / O (green) --- / S (blue) ... then a word gap, repeat.
//
// NOTE: Arduino IDE support is a separate, not-yet-validated slice. This sketch
// is validated through the Arduino CLI only (see docs/BUILD.md).
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#include <Arduino.h>

// Canonical implementation, from the TeensySos library (shared with the PlatformIO root).
#include <SosController.hpp>
#include <TeensyClock.hpp>
#include <TeensyRgbLedAdapter.hpp>

namespace {

// Concrete adapters (the composition root owns them).
sos::platform::TeensyRgbLedAdapter g_led;
sos::platform::TeensyClock g_clock;

// The controller binds to the adapters by reference (CTAD via deduction guide).
sos::app::SosController g_sos{g_led, g_clock};

}  // namespace

void setup() {
  g_led.begin();   // RGB channel pins; LED forced dark.
  g_sos.begin();   // Build the SOS program; start on the first segment.
}

void loop() { g_sos.poll(); }
