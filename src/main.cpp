// main.cpp - PlatformIO composition root for the SOS Morse RGB-LED demo.
//
// This is a THIN composition root: it owns the concrete adapters (RGB LED,
// millisecond clock) and wires them into the templated SosController. setup()
// does hardware bring-up; loop() pumps the controller. All wiring lives here so
// the composition root is explicit and the controller stays hardware-free.
//
// The SOS behavior itself is NOT implemented here - it lives once, canonically,
// in the TeensySos library (lib/TeensySos). The Arduino CLI composition root
// (arduino/teensy_sos/teensy_sos.ino) wires the SAME library the same way.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#include <Arduino.h>

// Canonical implementation, from the TeensySos library (shared with the Arduino root).
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

auto setup() -> void {
  g_led.begin();   // RGB channel pins; LED forced dark.
  g_sos.begin();   // Build the SOS program; start on the first segment.
}

auto loop() -> void { g_sos.poll(); }
