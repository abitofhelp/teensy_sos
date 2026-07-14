// Domain.hpp - Pure domain types for the SOS Morse demo.
//
// This is the innermost layer: no hardware, no framework, no I/O. It defines the
// vocabulary the whole demo is expressed in - a display Color, a Morse Symbol,
// and a timed Segment - plus the standard Morse timing constants. Everything here
// is host-testable and depends only on <cstdint>.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <cstdint>

namespace sos::domain {

// A color the RGB LED can show. Off means the LED is dark (used for Morse gaps).
enum class Color : uint8_t { Off, Red, Green, Blue };

// A Morse element: the short mark (Dot) or the long mark (Dash).
enum class Symbol : uint8_t { Dot, Dash };

// Standard Morse timing, expressed in "units" (T). One unit is the duration of a
// dot; the controller multiplies these by a wall-clock milliseconds-per-unit at
// run time. Ratios are the ITU standard: dash = 3T, symbol gap = 1T, letter gap
// = 3T, word gap = 7T.
inline constexpr uint16_t kDotUnits       = 1;  // short mark
inline constexpr uint16_t kDashUnits      = 3;  // long mark
inline constexpr uint16_t kIntraGapUnits  = 1;  // gap between symbols in a letter
inline constexpr uint16_t kLetterGapUnits = 3;  // gap between letters
inline constexpr uint16_t kWordGapUnits   = 7;  // gap between words (before repeat)

// A single timed step of the visual program: show `color` for `units` time-units.
// A Segment with color == Off is a gap (LED dark).
struct Segment {
  Color color;
  uint16_t units;

  friend constexpr bool operator==(const Segment&, const Segment&) = default;
};

}  // namespace sos::domain
