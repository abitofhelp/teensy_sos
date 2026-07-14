// MorseEncoder.hpp - Turn letters into a flat, timed Segment program.
//
// Domain-layer logic (no hardware, no clock): given a letter's color and its
// dot/dash pattern, append the corresponding ON segments and inter-symbol gaps
// to an output buffer, then build the full SOS program (S O S). The controller
// replays the program against a real clock; keeping the expansion pure here
// makes it exhaustively host-testable.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <cstddef>
#include <cstdint>

#include "Domain.hpp"

namespace sos::domain {

// A Morse letter: a display color plus its ordered dot/dash pattern.
struct Letter {
  Color color;
  const Symbol* symbols;
  size_t count;
};

// Upper bound on the segments the SOS program occupies (18 actual; padded).
inline constexpr size_t kSosSegmentCap = 32;

// Append one letter's ON/gap segments to `out` starting at `pos`. Between symbols
// an intra-letter gap (1T) is inserted; AFTER the letter, `trailing_gap_units` is
// emitted (a letter gap between letters, or a word gap at the end of the word).
// Never writes past `cap`, but always advances `pos` so the caller can detect an
// overflow (returned pos > cap). Returns the new position.
inline size_t encode_letter(const Letter& letter, uint16_t trailing_gap_units,
                            Segment* out, size_t cap, size_t pos) {
  for (size_t i = 0; i < letter.count; ++i) {
    const uint16_t on_units =
        (letter.symbols[i] == Symbol::Dash) ? kDashUnits : kDotUnits;
    if (pos < cap) out[pos] = Segment{letter.color, on_units};
    ++pos;
    if (i + 1 < letter.count) {  // gap between symbols within the letter
      if (pos < cap) out[pos] = Segment{Color::Off, kIntraGapUnits};
      ++pos;
    }
  }
  if (pos < cap) out[pos] = Segment{Color::Off, trailing_gap_units};
  ++pos;
  return pos;
}

// Fill `out` with the SOS program: S (red) . O (green) . S (blue), with a word
// gap after the final S so the pattern reads cleanly when it repeats. Writes at
// most `cap` segments and returns the number of segments the program REQUIRES
// (always 18 for SOS). If the return value exceeds `cap` the program was
// truncated and the caller must treat it as an error; pass `cap` >=
// kSosSegmentCap to guarantee the whole program fits.
inline size_t build_sos(Segment* out, size_t cap) {
  const Symbol dots[3]   = {Symbol::Dot, Symbol::Dot, Symbol::Dot};
  const Symbol dashes[3] = {Symbol::Dash, Symbol::Dash, Symbol::Dash};

  const Letter s_red{Color::Red, dots, 3};
  const Letter o_green{Color::Green, dashes, 3};
  const Letter s_blue{Color::Blue, dots, 3};

  size_t pos = 0;
  pos = encode_letter(s_red, kLetterGapUnits, out, cap, pos);
  pos = encode_letter(o_green, kLetterGapUnits, out, cap, pos);
  pos = encode_letter(s_blue, kWordGapUnits, out, cap, pos);
  return pos;
}

}  // namespace sos::domain
