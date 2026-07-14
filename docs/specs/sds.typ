// teensy_sos - Software Design Specification (SKELETON)
// Starter scaffold: real structure, minimal SOS content, fill-in markers.
// Build with `make specs`. Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#set document(title: "teensy_sos - Software Design Specification", author: "A Bit of Help, Inc.")
#set page(paper: "us-letter", margin: 2.2cm, numbering: "1")
#set text(font: "Libertinus Serif", size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")
#show raw.where(block: true): set text(size: 8.5pt)

#let todo(body) = block(
  fill: rgb("#fff3f3"), stroke: (paint: rgb("#cc6666"), thickness: 0.6pt, dash: "dashed"),
  radius: 3pt, inset: 8pt, width: 100%,
  [#text(fill: rgb("#aa3333"), weight: "bold")[STARTER - FILL IN: ] #text(style: "italic")[#body]],
)

#align(center)[
  #v(0.5cm)
  #text(19pt, weight: "bold")[Software Design Specification]
  #v(4pt) #text(13pt)[teensy_sos - SOS Morse RGB Demo]
  #v(2pt) #text(10pt, fill: gray)[SKELETON - starter scaffold; populate per project]
]
#v(0.5cm)

= Architecture overview

The design is a hybrid DDD / Clean / Hexagonal (Ports & Adapters) layering. The
authoritative narrative and diagrams live in `docs/ARCHITECTURE.md` and
`docs/diagrams/`; this section summarizes the design decisions that satisfy the SRS.

Dependencies point inward only: `sos::platform` (adapters) -> `sos::app` (ports +
controller) -> `sos::domain` (pure) ; `sos::core` (shared kernel) is available to all.

#todo[Embed or reference the layer diagram and state the module boundaries authoritatively.]

= Component design

/ *sos::core* (`Core.hpp`): `Option<T>`, `Result<T,E>`, `FixedQueue<T,N>` - allocation-free
  building blocks. AVAILABLE starter component; the trivial SOS demo uses none of it (kept
  for real firmware built from this template). Exercised by `test_core.cpp`.
/ *sos::domain* (`Domain.hpp`, `MorseEncoder.hpp`): `Color`/`Symbol`/`Segment` and
  `build_sos()` which expands S-O-S into a flat `Segment[]` program. Satisfies SRS-F-1,
  SRS-F-2, SRS-F-3.
/ *sos::app* (`Ports.hpp`, `SosController.hpp`): `LedPort`/`ClockPort` concepts and the
  templated `SosController` state machine.
/ *sos::platform* (`TeensyRgbLedAdapter.hpp`, `TeensyClock.hpp`): concrete adapters
  realizing the ports.

#todo[For each component, document its responsibility, interface, invariants, and the
requirements it satisfies.]

= Key design decisions

/ *DD-1* Concepts over vtables: Ports are C++20 concepts, not virtual interfaces -
  zero-overhead static dispatch, no vtables, embedded-friendly.
/ *DD-2* Non-blocking stepping: The controller owns the program buffer and steps it via
  unsigned-wrap elapsed-time math (correct across the `millis()` rollover).
/ *DD-3* Explicit composition: The canonical implementation lives once in the `TeensySos`
  library (`lib/TeensySos`); wiring lives in a thin composition root per command-line
  frontend (`src/main.cpp` for PlatformIO, `arduino/teensy_sos/teensy_sos.ino` for the
  Arduino CLI); no cross-layer globals and no duplicated logic.

#todo[Record additional design decisions with rationale and the alternatives considered.]

= Traceability

#todo[Map each design element back to the SRS requirement(s) it satisfies and forward to
the STG test(s) that verify it.]
