// teensy_sos - Software Test Guide / Plan (SKELETON)
// Starter scaffold: real structure, minimal SOS content, fill-in markers.
// Build with `make specs`. Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#set document(title: "teensy_sos - Software Test Guide", author: "A Bit of Help, Inc.")
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
  #text(19pt, weight: "bold")[Software Test Guide]
  #v(4pt) #text(13pt)[teensy_sos - SOS Morse RGB Demo]
  #v(2pt) #text(10pt, fill: gray)[SKELETON - starter scaffold; populate per project]
]
#v(0.5cm)

= Test strategy

Two tiers: (1) *host unit tests* that build the domain + application layers on any C++20
compiler with fake adapters - fast, hardware-free, run on every change; (2) *hardware
validation* that flashes the firmware and observes the physical behavior.

#todo[State entry/exit criteria, tooling, coverage goals, and how tests trace to SRS.]

= Host unit tests

Run all suites with `make test` (currently 65 checks, 0 failures):

/ *test_core.cpp*: `Option`/`Result`/`FixedQueue` behavior (SRS-N-1..3).
/ *test_morse.cpp*: `build_sos()` produces the correct 18-segment program - colors,
  durations, and gap ratios (SRS-F-1, SRS-F-2, SRS-F-3).
/ *test_sos_controller.cpp*: the controller, driven by `FakeLed` + `FakeClock`, emits the
  program's color sequence in order and wraps to repeat.

#todo[Add test cases as requirements grow; note each case's requirement ID.]

= Hardware validation

The end-to-end bench procedure and its recorded result are in
`docs/HARDWARE_VALIDATION.md` (build -> transfer -> flash -> observe SOS).

#todo[Formalize the pass/fail criteria and record each validation run with board, date,
and observed behavior.]

= Traceability

#todo[Provide the requirement-to-test matrix. Every `SRS-*` requirement must have at least
one verifying test (host or hardware).]
