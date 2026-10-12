<img src=".github/banner.svg" alt="SwiftRight, in development: one Swift codebase, real SwiftUI on macOS, a SwiftUI-semantics runtime on Windows" width="100%">

# SwiftRight

A Swift desktop application SDK for macOS & Windows, in development: one SwiftUI codebase, actual SwiftUI/AppKit on Mac & a SwiftRight-owned SwiftUI-semantics runtime on Windows, drawn by a Rust renderer on GPUI 0.2.2 with AccessKit.

**Status:** SR0 (dependency, host & slice qualification) is built and receipted but not closed, and work is paused since 11 October 2026 ([PENDING.md](PENDING.md)). The Windows renderer, bridge, runtime & the SliceApp example build and run; the last fully qualified build is tuple 11 (fixture matrix 320/320, cross-compare against the Mac oracle 16/16; [docs/sr0-status.md](docs/sr0-status.md)). Still open: the slice contract is not frozen, the Windows MSIX package fails one interrupted-update check (W08), & the decisions listed under PENDING in `docs/sr0-status.md`. This is not a released SDK and not a claim of complete SwiftUI compatibility.

## Where it stands

Work is paused since 11 October 2026 ([PENDING.md](PENDING.md)). SR0 evidence binds to one pinned set of builds (runtime commit, bridge header, renderer DLL hash, fixture binaries) recorded in [docs/sr0-snapshot.md](docs/sr0-snapshot.md); open items are in [docs/sr0-status.md](docs/sr0-status.md).

| Measured on tuple 11 | Result | Where |
|---|---|---|
| Fixture matrix, 16 configurations x 20 runs, on the pinned Windows renderer | 320/320 | [docs/sr0-snapshot.md](docs/sr0-snapshot.md) |
| Cross-compare of the same configurations against the macOS oracle | 16/16, 0 unallowed differences, 69 fault controls rejected | `probes/sr0-o/f1-cross/CROSS-ALL.md` |
| Bridge smoke, timeout mode and pixel assertions | 40/40, 41/41, 10/10 | `examples/BridgeSmoke/` |
| SliceApp packaged for both platforms | MSIX 0.1.0.0 and DMG 0.1.0 / 0.1.1 built; MSIX fails one interrupted-update check (W08) | `examples/SliceApp/`, [docs/sr0-status.md](docs/sr0-status.md) |

## How it will work

- On macOS, SwiftRight types will be SwiftUI's own types, with a direct AppKit escape hatch.
- On Windows, a SwiftRight-owned runtime will own identity, state lifetime, dependency tracking, bindings, environment, layout proposals, transactions and lifecycle, and will render through a versioned C ABI to the Rust renderer. GPUI is the first renderer; Slint remains an unqualified alternative. UI Automation accessibility is a prerequisite, not an assumption.
- Existing Rust engines will keep working: on Windows they load in-process as separate versioned DLLs behind their own C ABI, so a UI-only change does not rebuild the rendering stack.
- Parity will be a tested contract, never a promise. Every API in the published inventory will have a compile fixture, a behavioural trace recorded on macOS and a Windows replay; unsupported APIs will fail at Windows compile time.
- No compiler fork, no transpiler, no emulator for macOS binaries, no native WinUI controls, no second-language shell, and no AI service or network connection to render UI.

Source for each point: [docs/architecture.md](docs/architecture.md), section 1 (product definition and hard requirements) and section 3 (architecture decisions AD2 to AD8).

## Architecture

Read [SwiftRight architecture v0.5](docs/architecture.md), dated 8 October 2026, & [review history with v0.5 dispositions](docs/architecture-review.md#v05-sequential-adversarial-review-8-october-2026). The Windows renderer is a Rust cdylib on GPUI 0.2.2, AccessKit 0.25.1 & accesskit_windows 0.35.1 (`render/swiftright-render`), exposed to Swift through a versioned C ABI (0.6) that `packages/SwiftRightBridge` consumes. GPUI is the first renderer; Slint remains an unqualified alternative. UIA, IME & Narrator paths are exercised by the SR0 native-interaction probes, and the known limitations are listed in `docs/sr0-status.md`.

The plan covers package boundaries, native backends, state and binding semantics, platform services, existing Rust-engine reuse, tooling, packaging, migration, conformance tests, performance measurements, and long-term maintenance.

## Targets

Qualified targets are macOS 14 or later on Apple Silicon & Windows 11 x64 (`docs/sr0-status.md`, scope revision 1). Windows arm64 & Intel Macs are unsupported. The recorded hosts use Swift 6.4 on both platforms (`docs/sr0-snapshot.md`).

## Delivery sequence

| Gate | Required outcome | State |
| --- | --- | --- |
| SR0 | Qualify dependencies/hosts; freeze slice & budgets; establish repeatable Mac oracle; prove layout/bridge; compare seeds; qualify signed packages & local automation. Failures route to their owning layer; Slint must qualify before fallback use. | Open: receipts on tuple 11; freeze, W08 & listed decisions pending ([docs/sr0-status.md](docs/sr0-status.md)) |
| SR1 | Inventory contract: compile fixtures, macOS traces, Windows replays; unsupported APIs fail at Windows compile. | Factory draft specifications & spikes in [factory/](factory/README.md); nothing promoted |
| SR2 | Deliver a complete desktop utility with persistence, native services, and installable packages. | Not started |
| SR3 | Migrate one real feature against an existing engine, retaining a rollback path. | Not started |
| SR4 | Pass measured performance, reliability, clean-install, and update requirements. | Not started |
| SR5 | Support a second independent application and publish contributor and compatibility guidance. | Not started |

The full plan defines acceptance criteria and platform boundaries for each gate. Preserve native platform extensions and working Rust engines; do not require a compiler fork, transpiler, browser-based controls, second-language shell, or runtime AI access. SwiftRight remains independent of [RustRight](https://github.com/bogusyogi/rustright).

## Layout

| Path | Contents |
| --- | --- |
| `docs/` | Architecture, SR0 status, findings, snapshot, retry ledger & the SR1 plan |
| `render/swiftright-render/` | Rust GPUI renderer & its C ABI header |
| `packages/SwiftRightBridge/` | Swift bridge to the renderer ABI |
| `packages/SwiftRightServices/` | Swift client for Rust engines on the RightKit framed-sidecar wire |
| `examples/` | `SliceApp` (packaged example), `BridgeSmoke`, `BridgeGeoModal` |
| `probes/` | SR0 probe projects & results; `sr0-s/fresh-runtime` holds the Swift runtime that `SliceApp` depends on |
| `factory/` | SR1 factory specifications, tools & spikes (draft) |
| `qualification/` | Qualification runner, receipts & outputs |
| `conformance/` | SR0 slice contract (draft) with accepted & candidate recordings |

SwiftRight owns UI semantics & Swift adapters; RightKit supplies existing shared capabilities, managed Rust builds & release machinery. This repository qualifies on local native hosts, without GitHub Actions.

## Licence

No licence has been chosen yet. Until a licence file is added, all rights are reserved; the source is published for reading.

---

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/orthic-labs-mark.svg"><img src=".github/orthic-labs-mark-light.svg" alt="Orthic Labs" width="22" style="max-width:100%;height:auto"></picture> **[Orthic Labs](https://orthiclabs.com)** · [github.com/Orthic-Labs](https://github.com/Orthic-Labs) · More: [Legion](https://github.com/Orthic-Labs/legion) · [SellRight](https://github.com/Orthic-Labs/sellright) · [Ember](https://github.com/Orthic-Labs/ember) · [Pulse](https://github.com/Orthic-Labs/pulse) · [RightKit](https://github.com/Orthic-Labs/rightkit) · [RustRight](https://github.com/Orthic-Labs/rustright)
