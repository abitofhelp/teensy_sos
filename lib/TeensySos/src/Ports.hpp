// Ports.hpp - The application layer's driven-port concepts.
//
// These C++20 concepts are the hexagonal boundary: the SosController is written
// against them, never against Arduino or any concrete pin/clock. On the device a
// TeensyRgbLedAdapter + TeensyClock satisfy them; in host tests a FakeLed +
// FakeClock do. Nothing here includes a framework header.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <concepts>
#include <cstdint>

#include "Domain.hpp"

namespace sos::app {

// A display the controller can drive to a single color at a time. The controller
// calls set() from a noexcept context and ignores any return, so the port must
// offer a non-throwing `void set(Color)` - the concept requires exactly that so a
// throwing or wrong-signature adapter fails to compile rather than at run time.
template <typename T>
concept LedPort = requires(T& led, sos::domain::Color color) {
  { led.set(color) } noexcept -> std::same_as<void>;
};

// A monotonic millisecond clock. millis() must be a non-throwing, const-callable
// accessor returning exactly uint32_t; it must wrap cleanly (unsigned) so the
// controller's elapsed-time math stays correct across the 32-bit rollover.
template <typename T>
concept ClockPort = requires(const T& clock) {
  { clock.millis() } noexcept -> std::same_as<uint32_t>;
};

}  // namespace sos::app
