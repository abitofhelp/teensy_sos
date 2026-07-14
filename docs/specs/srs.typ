// teensy_sos - Software Requirements Specification (SKELETON)
// Starter scaffold: real structure, minimal SOS content, fill-in markers.
// Build with `make specs`. Copyright (c) 2026 Michael Gardner, A Bit of Help, Inc. BSD-3-Clause.

#set document(title: "teensy_sos - Software Requirements Specification", author: "A Bit of Help, Inc.")
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
  #text(19pt, weight: "bold")[Software Requirements Specification]
  #v(4pt) #text(13pt)[teensy_sos - SOS Morse RGB Demo]
  #v(2pt) #text(10pt, fill: gray)[SKELETON - starter scaffold; populate per project]
]
#v(0.5cm)

= Purpose and scope

This document specifies *what* the software must do, independent of *how*. For this
starter it is intentionally minimal - the SOS demo has a tiny requirement set - but the
section structure is the one every project in this family should follow.

#todo[State the system's purpose, its stakeholders, and the boundary of what is / is not
in scope for this release.]

= Definitions, acronyms, references

/ Morse unit (T): the base time interval; a dot is 1T (see @sec-func).
/ Segment: a timed display step - one color held for N units (or a dark gap).

#todo[Add domain glossary terms, external standards, and cross-references to the SDS and
STG.]

= Functional requirements <sec-func>

Requirements are numbered `SRS-F-n` and each traces to a design element (SDS) and a test
(STG). Two concrete examples are given; the rest is scaffold.

/ *SRS-F-1* (SOS pattern): The system shall emit the Morse sequence for "SOS" - three
  dots, three dashes, three dots - repeating indefinitely.
/ *SRS-F-2* (Color coding): The system shall display the first letter in red, the second
  in green, and the third in blue, with the display dark during all gaps.
/ *SRS-F-3* (Timing ratios): The system shall use standard Morse ratios (dash = 3x dot;
  symbol gap = 1x; letter gap = 3x; word gap = 7x).

#todo[Add remaining functional requirements. Each must be atomic, testable, and traceable.]

= Non-functional requirements

/ *SRS-N-1* (No dynamic allocation): The firmware shall not use the heap.
/ *SRS-N-2* (No exceptions / RTTI): The firmware shall build with exceptions and RTTI
  disabled.
/ *SRS-N-3* (Host-testable): The domain and application logic shall be unit-testable on a
  host with no target hardware.

#todo[Add performance, memory, portability, and reliability requirements as the project
grows.]

= Constraints and assumptions

/ Target: Teensy 4.1 (IMXRT1062), Arduino framework, built via the PlatformIO CLI or the
  Arduino CLI (both compile the same canonical library).
/ Display: a single common-cathode RGB LED (see `docs/HARDWARE.md`).

#todo[List hardware, toolchain, regulatory, and environmental constraints.]

= Traceability

#todo[Provide the requirements-to-design (SDS) and requirements-to-test (STG) traceability
matrix. Every `SRS-*` must map to at least one design element and one test.]
