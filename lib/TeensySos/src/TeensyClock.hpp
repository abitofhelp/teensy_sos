// TeensyClock.hpp - Infrastructure adapter: the Arduino millisecond clock.
//
// Satisfies sos::app::ClockPort by forwarding to Arduino's millis(). Trivial, but
// keeping it behind the port means the controller can be driven by a fake clock
// in host tests with zero hardware.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <Arduino.h>

#include <cstdint>

#include "Ports.hpp"

namespace sos::platform {

class TeensyClock {
 public:
  [[nodiscard]] auto millis() const noexcept -> uint32_t {
    return static_cast<uint32_t>(::millis());
  }
};

// Compile-time proof that the real adapter satisfies its driven port.
static_assert(sos::app::ClockPort<TeensyClock>,
              "TeensyClock must satisfy sos::app::ClockPort");

}  // namespace sos::platform
