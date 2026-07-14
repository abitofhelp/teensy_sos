// TeensyRgbLedAdapter.hpp - Infrastructure adapter: drive a 4-lead RGB LED.
//
// Satisfies sos::app::LedPort by mapping a domain Color onto three GPIO channels.
// This is the ONLY file in the SOS path that knows about pins or Arduino; the
// controller stays hardware-free behind the LedPort concept.
//
// Wiring (breadboard POC, common-CATHODE): the LED's common lead goes to GND, so
// a channel lights when its pin is driven HIGH (non-inverted). Each color leg is
// resistor-protected. Pins: R -> 18, G -> 14, B -> 15. Flip kCommonAnode to true
// for a common-ANODE part (common to 3V3, pins active-LOW).
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <Arduino.h>

#include "Domain.hpp"
#include "Ports.hpp"

namespace sos::platform {

class TeensyRgbLedAdapter {
 public:
  static constexpr uint8_t kRedPin   = 18;
  static constexpr uint8_t kGreenPin = 14;
  static constexpr uint8_t kBluePin  = 15;
  // Common-cathode part: common -> GND, pins active-HIGH. Set true for common-anode.
  static constexpr bool kCommonAnode = false;

  // Configure the channel pins and start dark. Call once from setup().
  void begin() noexcept {
    pinMode(kRedPin, OUTPUT);
    pinMode(kGreenPin, OUTPUT);
    pinMode(kBluePin, OUTPUT);
    set(sos::domain::Color::Off);
  }

  // Drive exactly one channel (or none, for Off). LedPort requirement.
  void set(sos::domain::Color color) noexcept {
    using sos::domain::Color;
    drive(kRedPin,   color == Color::Red);
    drive(kGreenPin, color == Color::Green);
    drive(kBluePin,  color == Color::Blue);
  }

 private:
  // Translate "channel on?" into the electrically correct pin level for the part.
  static void drive(uint8_t pin, bool on) noexcept {
    const bool level = kCommonAnode ? !on : on;
    digitalWriteFast(pin, level ? HIGH : LOW);
  }
};

// Compile-time proof that the real adapter satisfies its driven port. If the
// set() signature ever drifts (return type, constness, noexcept) this fails to
// compile here rather than at the controller's instantiation site.
static_assert(sos::app::LedPort<TeensyRgbLedAdapter>,
              "TeensyRgbLedAdapter must satisfy sos::app::LedPort");

}  // namespace sos::platform
