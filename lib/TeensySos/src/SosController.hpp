// SosController.hpp - The application layer: a hardware-free SOS state machine.
//
// Templated over the driven ports (an LedPort and a ClockPort), the controller
// owns the timed SOS program and steps through it non-blocking: each poll() reads
// the clock, and when the current segment's hold time has elapsed it advances to
// the next segment (wrapping at the end) and drives the LED to that segment's
// color. All timing is derived from a single milliseconds-per-Morse-unit value,
// so the whole pattern speeds up or slows down with one constructor argument.
//
// The design is the canonical controller shape for this template: concept-bound
// ports, a deduction guide for CTAD, and unsigned-wrap elapsed-time math - here
// wrapped around a trivial, non-proprietary domain.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <cstddef>
#include <cstdint>

#include "Domain.hpp"
#include "MorseEncoder.hpp"
#include "Ports.hpp"

namespace sos::app {

template <LedPort Led, ClockPort Clock>
class SosController {
 public:
  // A time-unit (one Morse dot) defaults to 200 ms - a comfortable visual pace.
  static constexpr uint16_t kDefaultUnitMs = 200;

  // unit_ms is clamped to a minimum of 1: a zero unit would make every segment's
  // hold time zero, so poll() would advance on every call at the same timestamp
  // (a spin, not a blink). Clamping keeps the state machine well-defined.
  SosController(Led& led, Clock& clock, uint16_t unit_ms = kDefaultUnitMs) noexcept
      : led_(led), clock_(clock), unit_ms_(unit_ms == 0 ? 1 : unit_ms) {}

  // Build the SOS program and start on its first segment. Call once from setup().
  // build_sos() returns the number of segments the program REQUIRES; if that ever
  // exceeds the fixed buffer the program was truncated, so we fail closed (empty
  // program, LED dark) rather than silently replaying an incomplete pattern.
  void begin() noexcept {
    const size_t required = sos::domain::build_sos(program_, kCap);
    if (required > kCap) {  // truncated: refuse to replay a partial program
      count_ = 0;
      pos_ = 0;
      led_.set(sos::domain::Color::Off);
      return;
    }
    count_ = required;
    pos_ = 0;
    seg_start_ = clock_.millis();
    apply();
  }

  // Advance the state machine if the current segment's hold time has elapsed.
  // Non-blocking: call every loop() iteration. A single poll() advances at most
  // one segment; if a poll is very late (more than one segment overdue) the extra
  // lateness is dropped and the next segment starts at `now` - the sequence
  // phase-shifts but never skips a segment. That is the intended behavior for a
  // visual demo serviced in a tight loop.
  void poll() noexcept {
    if (count_ == 0) return;
    const uint32_t now = clock_.millis();
    const uint32_t hold =
        static_cast<uint32_t>(program_[pos_].units) * unit_ms_;
    // Unsigned subtraction is wrap-safe across the 32-bit millis() rollover,
    // provided poll() is serviced at least once per counter period (~49.7 days).
    if (static_cast<uint32_t>(now - seg_start_) >= hold) {
      seg_start_ = now;
      pos_ = (pos_ + 1 == count_) ? 0 : pos_ + 1;  // wrap -> repeat SOS
      apply();
    }
  }

 private:
  static constexpr size_t kCap = sos::domain::kSosSegmentCap;

  void apply() noexcept { led_.set(program_[pos_].color); }

  Led& led_;
  Clock& clock_;
  uint16_t unit_ms_;
  sos::domain::Segment program_[kCap]{};
  size_t count_ = 0;
  size_t pos_ = 0;
  uint32_t seg_start_ = 0;
};

// Deduction guides so the composition root can write `SosController c{led, clock}`
// (or with an explicit unit_ms) without naming the port types.
template <typename L, typename C>
SosController(L&, C&) -> SosController<L, C>;
template <typename L, typename C>
SosController(L&, C&, uint16_t) -> SosController<L, C>;

}  // namespace sos::app
