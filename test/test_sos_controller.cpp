// test_sos_controller.cpp - Host-side tests for the SOS state machine.
//
// Drives SosController with a FakeLed (records every color it is set to) and a
// FakeClock (host-controlled millis()), then checks that the emitted color
// sequence matches the SOS program segment-for-segment and wraps to repeat.
//
// Build & run (or just `make test`):
//   c++ -std=c++20 -I../lib/TeensySos/src test_sos_controller.cpp -o test_sos && ./test_sos
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <type_traits>
#include <utility>

#include "MorseEncoder.hpp"
#include "SosController.hpp"

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

using sos::domain::Color;
using sos::domain::Segment;

// Test doubles satisfying the driven ports (no hardware).
struct FakeLed {
  static constexpr size_t kCap = 128;
  Color log[kCap] = {};
  size_t count = 0;
  Color last = Color::Off;
  void set(Color c) noexcept {
    last = c;
    if (count < kCap) log[count++] = c;
  }
};

struct FakeClock {
  uint32_t now = 0;
  [[nodiscard]] auto millis() const noexcept -> uint32_t { return now; }
};

// Compile-time proof that the fakes satisfy the driven ports and that CTAD
// deduces the controller type from them for both constructor forms.
static_assert(sos::app::LedPort<FakeLed>, "FakeLed must satisfy LedPort");
static_assert(sos::app::ClockPort<FakeClock>, "FakeClock must satisfy ClockPort");
static_assert(
    std::is_same_v<decltype(sos::app::SosController{std::declval<FakeLed&>(),
                                                    std::declval<FakeClock&>()}),
                   sos::app::SosController<FakeLed, FakeClock>>,
    "CTAD (2-arg) deduces SosController<FakeLed, FakeClock>");
static_assert(
    std::is_same_v<decltype(sos::app::SosController{std::declval<FakeLed&>(),
                                                    std::declval<FakeClock&>(),
                                                    uint16_t{50}}),
                   sos::app::SosController<FakeLed, FakeClock>>,
    "CTAD (3-arg) deduces SosController<FakeLed, FakeClock>");

// Negative cases: malformed adapter shapes must be REJECTED by the concepts, so
// a wrong signature fails to compile at the adapter, not deep in the controller.
struct BadLedWrongReturn { int set(Color) noexcept; };            // returns int
struct BadLedThrows { void set(Color); };                         // not noexcept
struct BadClockNonConst { uint32_t millis() noexcept; };          // not const
struct BadClockWrongType { uint16_t millis() const noexcept; };   // wrong type
static_assert(!sos::app::LedPort<BadLedWrongReturn>, "non-void set() is rejected");
static_assert(!sos::app::LedPort<BadLedThrows>, "throwing set() is rejected");
static_assert(!sos::app::ClockPort<BadClockNonConst>, "non-const millis() is rejected");
static_assert(!sos::app::ClockPort<BadClockWrongType>, "wrong millis() type is rejected");

// Independent oracle: the full SOS program written by hand (color + exact unit
// count), NOT produced by build_sos(). The controller builds its own program
// internally, so comparing against this table means an encoder defect cannot
// corrupt both the controller's input and the test's expectation.
constexpr Segment kExpectedSos[] = {
    {Color::Red, 1},   {Color::Off, 1}, {Color::Red, 1},   {Color::Off, 1},
    {Color::Red, 1},   {Color::Off, 3},
    {Color::Green, 3}, {Color::Off, 1}, {Color::Green, 3}, {Color::Off, 1},
    {Color::Green, 3}, {Color::Off, 3},
    {Color::Blue, 1},  {Color::Off, 1}, {Color::Blue, 1},  {Color::Off, 1},
    {Color::Blue, 1},  {Color::Off, 7},
};
constexpr size_t kExpectedSosLen = sizeof(kExpectedSos) / sizeof(kExpectedSos[0]);

void test_controller_replays_sos() {
  std::printf("test_controller_replays_sos\n");

  uint32_t total_units = 0;
  for (size_t i = 0; i < kExpectedSosLen; ++i) total_units += kExpectedSos[i].units;

  FakeLed led;
  FakeClock clk;
  // 1 ms per Morse unit so each unit is one clock tick - easy, exact stepping.
  sos::app::SosController ctl(led, clk, 1);

  clk.now = 0;
  ctl.begin();  // the controller builds its OWN program internally
  check(led.count == 1, "begin() applies exactly one color");
  check(led.log[0] == kExpectedSos[0].color, "begins on the first segment color (red)");

  // Tick the clock one millisecond at a time through one full cycle. Because a
  // segment holds for `units` ms and seg_start resets on each transition, exactly
  // one transition fires at each cumulative boundary.
  for (uint32_t t = 1; t <= total_units; ++t) {
    clk.now = t;
    ctl.poll();
  }

  check(led.count == kExpectedSosLen + 1,
        "one color per segment, plus the wrap back to segment 0");

  bool matches = true;
  for (size_t i = 0; i < kExpectedSosLen; ++i) {
    if (led.log[i] != kExpectedSos[i].color) matches = false;
  }
  check(matches, "emitted color sequence matches the independent SOS table");
  check(led.log[kExpectedSosLen] == kExpectedSos[0].color,
        "program wraps back to the first color (repeats)");
}

void test_rollover_with_multi_ms_unit() {
  std::printf("test_rollover_with_multi_ms_unit\n");
  // Covers the multiplication (units * unit_ms) AND the unsigned wrap together:
  // a non-1 unit_ms with the segment's hold boundary straddling the 32-bit
  // millis() rollover. hold-1 must not advance; exactly hold must advance.
  FakeLed led;
  FakeClock clk;
  const uint16_t unit_ms = 200;
  sos::app::SosController ctl(led, clk, unit_ms);  // first hold = 1 unit * 200 ms

  const uint32_t start = 0u - 100u;  // 0xFFFFFF9C == 2^32 - 100; the hold crosses the wrap
  clk.now = start;
  ctl.begin();
  check(led.count == 1, "begin applies one color just before the rollover");

  clk.now = start + (1u * unit_ms) - 1u;  // 199 ms elapsed (wrapped): still holding
  ctl.poll();
  check(led.count == 1, "no advance at hold-1 (199<200): multiplication honored across the wrap");

  clk.now = start + (1u * unit_ms);       // exactly 200 ms elapsed (wrapped): advance
  ctl.poll();
  check(led.count == 2, "advances at exactly hold (1*200) across the millis() rollover");
}

void test_controller_holds_between_ticks() {
  std::printf("test_controller_holds_between_ticks\n");
  FakeLed led;
  FakeClock clk;
  sos::app::SosController ctl(led, clk, 200);  // 200 ms per unit

  clk.now = 1000;
  ctl.begin();
  const Color first = led.last;

  clk.now = 1100;  // only 100 ms elapsed; first segment (dot) holds 200 ms
  ctl.poll();
  check(led.last == first && led.count == 1, "no transition before the hold elapses");

  clk.now = 1200;  // 200 ms elapsed -> advance to the intra-letter gap (off)
  ctl.poll();
  check(led.last == Color::Off, "advances to the off gap once the dot's 200 ms elapses");
}

void test_zero_unit_ms_is_clamped() {
  std::printf("test_zero_unit_ms_is_clamped\n");
  FakeLed led;
  FakeClock clk;
  sos::app::SosController ctl(led, clk, 0);  // must clamp to 1, not spin
  clk.now = 0;
  ctl.begin();
  check(led.count == 1, "begin applies exactly one color");
  ctl.poll();  // same timestamp: a zero unit would make hold==0 and advance here
  check(led.count == 1, "zero unit_ms is clamped: no advance at the same timestamp");
  clk.now = 1;
  ctl.poll();
  check(led.count == 2, "advances after 1 ms with the clamped unit");
}

void test_survives_millis_rollover() {
  std::printf("test_survives_millis_rollover\n");
  Segment prog[sos::domain::kSosSegmentCap];
  sos::domain::build_sos(prog, sos::domain::kSosSegmentCap);

  FakeLed led;
  FakeClock clk;
  sos::app::SosController ctl(led, clk, 1);  // 1 ms per unit

  clk.now = 0xFFFFFFFEu;  // two ticks before the 32-bit rollover
  ctl.begin();
  check(led.log[0] == prog[0].color, "starts on the first color near the rollover");
  clk.now = 0xFFFFFFFFu;  // elapsed 1 -> advance
  ctl.poll();
  check(led.log[1] == prog[1].color, "advances at the last tick before rollover");
  clk.now = 0x00000000u;  // wrapped; unsigned elapsed == 1 -> advance
  ctl.poll();
  check(led.log[2] == prog[2].color, "advances correctly across the millis() rollover");
}

void test_delayed_poll_advances_one_segment() {
  std::printf("test_delayed_poll_advances_one_segment\n");
  FakeLed led;
  FakeClock clk;
  sos::app::SosController ctl(led, clk, 1);
  clk.now = 0;
  ctl.begin();          // count == 1
  clk.now = 100000;     // hugely overdue (many segments' worth)
  ctl.poll();
  check(led.count == 2, "a very late poll advances exactly one segment (never skips)");
  ctl.poll();           // same timestamp
  check(led.count == 2, "no further advance without more elapsed time (lateness dropped)");
}

void test_repeated_begin_resets() {
  std::printf("test_repeated_begin_resets\n");
  Segment prog[sos::domain::kSosSegmentCap];
  sos::domain::build_sos(prog, sos::domain::kSosSegmentCap);

  FakeLed led;
  FakeClock clk;
  sos::app::SosController ctl(led, clk, 1);
  clk.now = 0;
  ctl.begin();
  clk.now = 1;
  ctl.poll();  // -> segment 1
  clk.now = 2;
  ctl.poll();  // -> segment 2
  ctl.begin();  // restart
  check(led.last == prog[0].color, "begin() resets to the first segment color");
}

}  // namespace

int main() {
  test_controller_replays_sos();
  test_controller_holds_between_ticks();
  test_zero_unit_ms_is_clamped();
  test_survives_millis_rollover();
  test_rollover_with_multi_ms_unit();
  test_delayed_poll_advances_one_segment();
  test_repeated_begin_resets();
  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
