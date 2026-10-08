# SwiftRight

A proposed Swift desktop application SDK for macOS and Windows: one SwiftUI codebase, actual SwiftUI/AppKit on Mac, and a SwiftRight-owned SwiftUI-semantics runtime on Windows rendering through GPUI.

**Status:** architecture and implementation planning. The shared UI facade, selected dependencies, packaging, and performance still require prototype validation. This is not a released SDK or a claim of complete SwiftUI compatibility.

## Architecture and implementation plan

Read the [full SwiftRight architecture plan](docs/architecture.md), version 0.3, dated 8 October 2026, with an [adversarial review](docs/architecture-review.md) that drove the v0.2 and v0.3 changes.

The plan covers package boundaries, native backends, state and binding semantics, platform services, existing Rust-engine reuse, tooling, packaging, migration, conformance tests, performance measurements, and long-term maintenance.

## Delivery sequence

| Gate | Required outcome |
| --- | --- |
| SR0 | Eight-week decision slice: bridge ABI + GPUI renderer prebuilt for x64 & arm64, two runtime seeds compared by Mac-trace replay, UIA gate, clean-VM packaging, automation jobs. Kill criteria & Slint plan B inside one codebase. |
| SR1 | Inventory contract: compile fixtures, macOS traces, Windows replays; unsupported APIs fail at Windows compile. |
| SR2 | Deliver a complete desktop utility with persistence, native services, and installable packages. |
| SR3 | Migrate one real feature against an existing engine, retaining a rollback path. |
| SR4 | Pass measured performance, reliability, clean-install, and update requirements. |
| SR5 | Support a second independent application and publish contributor and compatibility guidance. |

The full plan defines acceptance criteria and platform boundaries for each gate. Preserve native platform extensions and working Rust engines; do not require a compiler fork, transpiler, browser-based controls, second-language shell, or runtime AI access. SwiftRight remains independent of [RustRight](https://github.com/bogusyogi/rustright).
