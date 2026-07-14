// Core.hpp - Minimal, header-only, embedded-friendly building blocks.
//
// Contains the small Result<T, E> / Option<T> monads mandated by the C++ house
// standard and a fixed-capacity SPSC ring buffer (FixedQueue). All three are
// noexcept, allocation-free, RTTI-free, and depend only on <cstdint>/<cstddef>.
// They are safe to include from host-side unit tests.
//
// This is the reusable shared kernel of the starter template; it is domain-free
// and general-purpose. The trivial SOS demo uses NONE of it - it is kept so that
// real firmware built from this template has the building blocks (Option/Result
// on cold paths, an ISR-fed FixedQueue) already present and demonstrated. It is
// exercised by test_core.cpp regardless.
//
// Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>

namespace sos::core {

// ---------------------------------------------------------------------------
// Option<T> - an explicit "value or nothing", replacing sentinel returns.
// ---------------------------------------------------------------------------
template <typename T>
class Option {
 public:
  constexpr Option() noexcept : has_value_(false), value_{} {}
  constexpr explicit Option(const T& value) noexcept
      : has_value_(true), value_(value) {}

  [[nodiscard]] static constexpr auto none() noexcept -> Option { return Option{}; }
  [[nodiscard]] static constexpr auto some(const T& value) noexcept -> Option {
    return Option{value};
  }

  [[nodiscard]] constexpr auto has_value() const noexcept -> bool { return has_value_; }
  [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value_; }

  // Precondition: has_value() is true. Never throws; reading an empty Option
  // returns the default-constructed T so behaviour stays deterministic.
  [[nodiscard]] constexpr auto value() const noexcept -> const T& { return value_; }
  // Returns the contained value, or `fallback` when empty. Mirrors
  // std::optional::value_or: the result is returned BY VALUE, so binding it to a
  // reference can never dangle even when the caller passes a temporary fallback.
  [[nodiscard]] constexpr auto value_or(T fallback) const noexcept -> T {
    return has_value_ ? value_ : fallback;
  }

 private:
  bool has_value_;
  T value_;
};

// ---------------------------------------------------------------------------
// Result<T, E> - a success value or a typed error, with no exceptions.
// ---------------------------------------------------------------------------
template <typename T, typename E>
class Result {
 public:
  [[nodiscard]] static constexpr auto ok(const T& value) noexcept -> Result {
    return Result{true, value, E{}};
  }
  [[nodiscard]] static constexpr auto err(E error) noexcept -> Result {
    return Result{false, T{}, error};
  }

  [[nodiscard]] constexpr auto is_ok() const noexcept -> bool { return is_ok_; }
  [[nodiscard]] constexpr auto is_err() const noexcept -> bool { return !is_ok_; }
  [[nodiscard]] constexpr explicit operator bool() const noexcept { return is_ok_; }

  // Precondition: is_ok(). Reading value() on an error returns a default T.
  [[nodiscard]] constexpr auto value() const noexcept -> const T& { return value_; }
  // Precondition: is_err(). Reading error() on a success returns a default E.
  [[nodiscard]] constexpr auto error() const noexcept -> E { return error_; }

 private:
  constexpr Result(bool is_ok, const T& value, E error) noexcept
      : is_ok_(is_ok), value_(value), error_(error) {}

  bool is_ok_;
  T value_;
  E error_;
};

// ---------------------------------------------------------------------------
// FixedQueue<T, Capacity> - lock-free single-producer / single-consumer ring.
//
// Concurrency contract: exactly ONE producer (may be an ISR) calling push(),
// and exactly ONE consumer (the main loop) calling pop(). The head_/tail_
// indices are std::atomic<uint32_t> synchronized with acquire/release ordering:
// push() writes the slot and then publishes it with a RELEASE store to head_;
// pop() observes head_ with an ACQUIRE load before reading the slot, so the
// item write happens-before the item read. This is a real C++ synchronization
// protocol - not merely a reliance on natural 32-bit load/store atomicity - so
// the ISR-to-main hand-off is well-defined, and it still lowers to plain loads
// and stores on single-core Cortex-M. Each side owns exactly one index, so no
// critical section is needed. Do NOT share a queue across multiple producers or
// multiple consumers.
//
// One slot is always left empty to distinguish full from empty, so the usable
// capacity is Capacity - 1. push() returns false when full (the caller counts
// the overflow); pop() returns Option::none() when empty.
// ---------------------------------------------------------------------------
template <typename T, size_t Capacity>
class FixedQueue {
  static_assert(Capacity >= 2, "FixedQueue needs at least 2 slots");
  static_assert(std::atomic<uint32_t>::is_always_lock_free,
                "FixedQueue requires lock-free 32-bit atomics (true on Cortex-M)");

 public:
  [[nodiscard]] auto push(const T& item) noexcept -> bool {
    const uint32_t head = head_.load(std::memory_order_relaxed);  // producer owns head_
    const uint32_t next = increment(head);
    if (next == tail_.load(std::memory_order_acquire)) {
      return false;  // Full.
    }
    buffer_[head] = item;
    head_.store(next, std::memory_order_release);  // Publish only after the slot is written.
    return true;
  }

  [[nodiscard]] auto pop() noexcept -> Option<T> {
    const uint32_t tail = tail_.load(std::memory_order_relaxed);  // consumer owns tail_
    if (tail == head_.load(std::memory_order_acquire)) {
      return Option<T>::none();  // Empty.
    }
    const T item = buffer_[tail];
    tail_.store(increment(tail), std::memory_order_release);  // Release only after the slot is read.
    return Option<T>::some(item);
  }

  // Return the front item WITHOUT removing it. Enables peek -> use -> pop-on-
  // success so a consumer (e.g. a send that may fail) never loses the item.
  // Consumer-side only, same SPSC contract as pop().
  [[nodiscard]] auto peek() const noexcept -> Option<T> {
    const uint32_t tail = tail_.load(std::memory_order_relaxed);
    if (tail == head_.load(std::memory_order_acquire)) {
      return Option<T>::none();
    }
    return Option<T>::some(buffer_[tail]);
  }

  [[nodiscard]] auto empty() const noexcept -> bool {
    return head_.load(std::memory_order_acquire) == tail_.load(std::memory_order_acquire);
  }

  [[nodiscard]] auto count() const noexcept -> size_t {
    const uint32_t head = head_.load(std::memory_order_acquire);
    const uint32_t tail = tail_.load(std::memory_order_acquire);
    return (head >= tail) ? (head - tail) : (Capacity - tail + head);
  }

  [[nodiscard]] static constexpr auto capacity() noexcept -> size_t { return Capacity - 1; }

 private:
  [[nodiscard]] static constexpr auto increment(uint32_t index) noexcept -> uint32_t {
    return (index + 1U == Capacity) ? 0U : index + 1U;
  }

  T buffer_[Capacity]{};
  std::atomic<uint32_t> head_{0};  // Written by producer, read by consumer.
  std::atomic<uint32_t> tail_{0};  // Written by consumer, read by producer.
};

}  // namespace sos::core
