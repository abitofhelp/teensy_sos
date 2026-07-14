// test_core.cpp - Host-side unit tests for the shared kernel.
//
// Build & run (or just `make test`):
//   c++ -std=c++20 -I../lib/TeensySos/src test_core.cpp -o test_core && ./test_core
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#include <cstdio>

#include "Core.hpp"

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

using sos::core::FixedQueue;
using sos::core::Option;
using sos::core::Result;

void test_option() {
  std::printf("test_option\n");
  auto none = Option<int>::none();
  check(!none.has_value(), "none has no value");
  check(none.value_or(7) == 7, "value_or returns the fallback when empty");

  auto some = Option<int>::some(42);
  check(some.has_value(), "some has a value");
  check(some.value() == 42, "some returns its value");
  check(some.value_or(7) == 42, "value_or returns the value when present");
}

struct Payload {
  int a;
  int b;
  friend constexpr bool operator==(const Payload&, const Payload&) = default;
};

void test_option_value_or_temporary() {
  std::printf("test_option_value_or_temporary\n");
  // value_or returns BY VALUE, so binding the result to a reference is safe even
  // when the fallback is a temporary. Returning const T& here would dangle - an
  // ASan build would trap on a stack-use-after-scope.
  const auto& from_empty = Option<Payload>::none().value_or(Payload{7, 8});
  check(from_empty == (Payload{7, 8}), "value_or returns the temporary fallback by value when empty");

  const auto& from_some = Option<Payload>::some(Payload{1, 2}).value_or(Payload{7, 8});
  check(from_some == (Payload{1, 2}), "value_or returns the contained value when present");
}

void test_result() {
  std::printf("test_result\n");
  enum class E { None, Bad };
  auto ok = Result<int, E>::ok(5);
  check(ok.is_ok() && !ok.is_err(), "ok is ok, not err");
  check(ok.value() == 5, "ok carries its value");

  auto err = Result<int, E>::err(E::Bad);
  check(err.is_err() && !err.is_ok(), "err is err, not ok");
  check(err.error() == E::Bad, "err carries its error");
}

void test_fixed_queue() {
  std::printf("test_fixed_queue\n");
  FixedQueue<int, 4> q;  // usable capacity = N - 1 = 3

  check(q.capacity() == 3, "usable capacity is N-1 (documented)");
  check(q.empty(), "new queue is empty");
  check(q.count() == 0, "new queue count is 0");
  check(!q.pop().has_value(), "empty pop returns none");
  check(!q.peek().has_value(), "empty peek returns none");

  check(q.push(10) && q.push(20) && q.push(30), "push up to usable capacity succeeds");
  check(q.count() == 3, "count reflects three fills");
  check(!q.push(40), "full queue rejects push");
  check(q.count() == 3, "rejected push did not change count");

  auto pk = q.peek();
  check(pk.has_value() && pk.value() == 10, "peek returns the front");
  check(q.count() == 3, "peek does not remove");
  auto p = q.pop();
  check(p.has_value() && p.value() == 10, "pop after peek returns the same item");
  check(q.count() == 2, "pop removed one");

  // Wraparound: the internal indices roll past the end of the ring.
  check(q.push(40), "push after a pop succeeds");   // buffer wraps here
  check(q.count() == 3, "count is 3 again");
  check(q.pop().value() == 20, "FIFO order preserved (20)");
  check(q.pop().value() == 30, "FIFO order preserved (30)");
  check(q.push(50) && q.push(60), "refill across the wrap boundary");
  check(q.count() == 3, "full again after wrap");
  check(!q.push(70), "still rejects when full after wraparound");

  check(q.pop().value() == 40, "wraparound order preserved (40)");
  check(q.pop().value() == 50, "wraparound order preserved (50)");
  check(q.pop().value() == 60, "wraparound order preserved (60)");
  check(q.empty(), "queue empty after draining");
  check(!q.pop().has_value(), "pop on a drained queue returns none");
}

}  // namespace

int main() {
  test_option();
  test_option_value_or_temporary();
  test_result();
  test_fixed_queue();
  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
