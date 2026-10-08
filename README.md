# SwiftRight

A proposed Swift desktop application SDK for macOS & Windows: one SwiftUI codebase, actual SwiftUI/AppKit on Mac & a SwiftRight-owned SwiftUI-semantics runtime on Windows, with GPUI as first renderer candidate.

**Status:** architecture and implementation planning. The SwiftUI-semantics runtime, selected dependencies, packaging, and performance still require prototype validation. This is not a released SDK or a claim of complete SwiftUI compatibility.

## Architecture and implementation plan

Read [SwiftRight architecture v0.5](docs/architecture.md), dated 8 October 2026, & [review history with v0.5 dispositions](docs/architecture-review.md#v05-sequential-adversarial-review-8-october-2026). Published GPUI 0.2.2 plus separate AccessKit Windows is first composition candidate; native UIA/text integration & host qualification remain prerequisites.

The plan covers package boundaries, native backends, state and binding semantics, platform services, existing Rust-engine reuse, tooling, packaging, migration, conformance tests, performance measurements, and long-term maintenance.

## Delivery sequence

| Gate | Required outcome |
| --- | --- |
| SR0 | Qualify dependencies/hosts; freeze slice & budgets; establish repeatable Mac oracle; prove layout/bridge; compare seeds; qualify signed packages & local automation. Failures route to their owning layer; Slint must qualify before fallback use. |
| SR1 | Inventory contract: compile fixtures, macOS traces, Windows replays; unsupported APIs fail at Windows compile. |
| SR2 | Deliver a complete desktop utility with persistence, native services, and installable packages. |
| SR3 | Migrate one real feature against an existing engine, retaining a rollback path. |
| SR4 | Pass measured performance, reliability, clean-install, and update requirements. |
| SR5 | Support a second independent application and publish contributor and compatibility guidance. |

The full plan defines acceptance criteria and platform boundaries for each gate. Preserve native platform extensions and working Rust engines; do not require a compiler fork, transpiler, browser-based controls, second-language shell, or runtime AI access. SwiftRight remains independent of [RustRight](https://github.com/bogusyogi/rustright).

SwiftRight owns UI semantics & Swift adapters; RightKit supplies existing shared capabilities, managed Rust builds & release machinery. This private repository qualifies on local native hosts, without GitHub Actions.
