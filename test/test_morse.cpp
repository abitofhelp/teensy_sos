// test_morse.cpp - Host-side unit tests for the Morse encoder / SOS program.
//
// Build & run (or just `make test`):
//   c++ -std=c++20 -I../lib/TeensySos/src test_morse.cpp -o test_morse && ./test_morse
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#include <cstddef>
#include <cstdio>

#include "MorseEncoder.hpp"

namespace {

int g_checks = 0;
int g_failures = 0;
void check(bool cond, const char* what) {
  ++g_checks;
  if (!cond) {
    ++g_failures;
    std::printf("  FAIL: %s\n", what);
  }
}

using namespace sos::domain;

void test_sos_program() {
  std::printf("test_sos_program\n");
  Segment prog[kSosSegmentCap];
  const size_t n = build_sos(prog, kSosSegmentCap);

  // S(3 dots) + O(3 dashes) + S(3 dots): each symbol is 1 ON segment, with a gap
  // between symbols (2 per letter) and a trailing gap per letter -> 5 + 1 each.
  check(n == 18, "SOS expands to 18 segments");
  check(n <= kSosSegmentCap, "program fits the documented capacity");

  // Letter S (red): dot gap dot gap dot, then a 3T letter gap.
  check(prog[0] == (Segment{Color::Red, kDotUnits}), "S starts on red dot (1T)");
  check(prog[1] == (Segment{Color::Off, kIntraGapUnits}), "intra-letter gap is 1T off");
  check(prog[2] == (Segment{Color::Red, kDotUnits}), "second red dot");
  check(prog[4] == (Segment{Color::Red, kDotUnits}), "third red dot");
  check(prog[5] == (Segment{Color::Off, kLetterGapUnits}), "letter gap after S is 3T off");

  // Letter O (green): dash gap dash gap dash, then a 3T letter gap.
  check(prog[6] == (Segment{Color::Green, kDashUnits}), "O starts on green dash (3T)");
  check(prog[11] == (Segment{Color::Off, kLetterGapUnits}), "letter gap after O is 3T off");

  // Letter S (blue): dot gap dot gap dot, then a 7T WORD gap (before repeat).
  check(prog[12] == (Segment{Color::Blue, kDotUnits}), "final S starts on blue dot (1T)");
  check(prog[16] == (Segment{Color::Blue, kDotUnits}), "third blue dot");
  check(prog[17] == (Segment{Color::Off, kWordGapUnits}),
        "word gap after final S is 7T off (spaces the repeat)");

  // No segment should be a zero-length or unknown color.
  bool all_positive = true;
  for (size_t i = 0; i < n; ++i) {
    if (prog[i].units == 0) all_positive = false;
  }
  check(all_positive, "every segment has a positive duration");
}

void test_sos_program_exact_table() {
  std::printf("test_sos_program_exact_table\n");
  // Independent oracle: the full 18-segment SOS program written out by hand
  // (color + exact unit count), NOT derived from build_sos(). A defect in the
  // encoder therefore cannot hide in both the code and the expectation.
  const Segment expected[18] = {
      {Color::Red, 1},   {Color::Off, 1}, {Color::Red, 1},   {Color::Off, 1},
      {Color::Red, 1},   {Color::Off, 3},                     // S + letter gap
      {Color::Green, 3}, {Color::Off, 1}, {Color::Green, 3}, {Color::Off, 1},
      {Color::Green, 3}, {Color::Off, 3},                     // O + letter gap
      {Color::Blue, 1},  {Color::Off, 1}, {Color::Blue, 1},  {Color::Off, 1},
      {Color::Blue, 1},  {Color::Off, 7},                     // S + word gap
  };

  Segment prog[kSosSegmentCap];
  const size_t n = build_sos(prog, kSosSegmentCap);
  check(n == 18, "SOS requires exactly 18 segments");
  bool exact = (n == 18);
  for (size_t i = 0; i < 18 && i < n; ++i) {
    if (!(prog[i] == expected[i])) exact = false;
  }
  check(exact, "every one of the 18 segments matches the hand-written table");
}

void test_build_sos_capacity_boundaries() {
  std::printf("test_build_sos_capacity_boundaries\n");
  // A distinctive sentinel lets us prove nothing is written past `cap`.
  const Segment sentinel{Color::Green, 12345};

  // cap == 0: writes nothing, but still reports the full requirement (18).
  {
    Segment buf[18];
    for (auto& s : buf) s = sentinel;
    const size_t req = build_sos(buf, 0);
    check(req == 18, "cap==0 reports required==18 (truncated)");
    check(buf[0] == sentinel, "cap==0 wrote no segments");
  }
  // cap == 17: one short; reports 18 (> cap) so truncation is detectable.
  {
    Segment buf[18];
    for (auto& s : buf) s = sentinel;
    const size_t req = build_sos(buf, 17);
    check(req == 18, "cap==17 reports required==18 (> cap: truncated)");
    check(!(buf[16] == sentinel), "cap==17 wrote through index 16");
    check(buf[17] == sentinel, "cap==17 did not write the 18th segment");
  }
  // cap == 18: exact fit; all 18 written, nothing truncated.
  {
    Segment buf[18];
    for (auto& s : buf) s = sentinel;
    const size_t req = build_sos(buf, 18);
    check(req == 18, "cap==18 reports required==18 (exact fit)");
    check(buf[17] == (Segment{Color::Off, kWordGapUnits}),
          "cap==18 wrote the final 7T word gap");
  }
}

void test_encode_letter_overflow_is_counted() {
  std::printf("test_encode_letter_overflow_is_counted\n");
  // A tiny buffer must not be written past, but pos still advances so an overflow
  // is detectable (returned pos > cap).
  const Symbol dots[3] = {Symbol::Dot, Symbol::Dot, Symbol::Dot};
  const Letter s{Color::Red, dots, 3};
  Segment tiny[2] = {};
  const size_t pos = encode_letter(s, kLetterGapUnits, tiny, 2, 0);
  check(pos > 2, "encode_letter reports the would-be overflow via pos > cap");
  check(tiny[0] == (Segment{Color::Red, kDotUnits}), "wrote only within capacity");
}

}  // namespace

int main() {
  test_sos_program();
  test_sos_program_exact_table();
  test_build_sos_capacity_boundaries();
  test_encode_letter_overflow_is_counted();
  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
