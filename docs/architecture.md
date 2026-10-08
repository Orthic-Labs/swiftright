# SwiftRight: one Swift codebase, real SwiftUI on Mac, SwiftUI-semantics runtime on Windows

Architecture v0.3 — 8 October 2026  
Status: proposed architecture; no implementation or measured performance claimed. v0.3 replaces the v0.2 Windows strategy (SwiftCrossUI over WinUI) with an owned SwiftUI-semantics runtime in Swift rendering through GPUI over a versioned C ABI. Rationale and the record of what changed are in `architecture-review.md`.

## 1. Product definition

Build a maintained desktop application SDK, not a Swift compiler fork, not a transpiler, and not an emulator for macOS binaries.

The target is **one Swift application codebase whose screens are real SwiftUI on macOS and retain their SwiftUI behaviour on Windows through a SwiftRight-owned runtime.** Existing Rust engines remain reusable and, on Windows, may run in-process with the renderer. A UI-only change should not rebuild the Rust rendering stack or an unchanged engine.

Hard requirements:

- One UI codebase. No second hand-maintained shell, no transitional third.
- Real SwiftUI and a direct AppKit escape hatch on macOS.
- On Windows: same source, same intended behaviour, accessible through UI Automation, Fluent-themed where cheap. Not native WinUI controls. Custom-drawn rendering is the same class as the current Tauri/WebView2 shell and is accepted.
- Shipped applications never require Claude, GPT, a network connection, or an AI subscription to render UI or call platform services.

Parity contract: SwiftUI behaviour for a published API inventory, proven by conformance traces recorded on macOS and replayed on Windows. A named SwiftUI SDK version is the ceiling that bounds the inventory, not a promise to implement everything in it.

## 2. Verified starting points

Swift ships Windows toolchains for x86_64 and arm64, a Windows Workgroup since January 2026, and Swift Build as the coming cross-platform default build system. The Browser Company continues toolchain, symbol-server, and static-stdlib work on Windows and was hiring for it in May 2026. Apple's cross-platform investment is in language and toolchain; SwiftUI itself remains Apple-only. [S1, S2, S10, S11, S12, S13]

GPUI, Zed's Rust UI framework, is published as a standalone crate (0.2.x), Apache-2.0, with a Windows backend on Win32 and DirectWrite, an unconditional `accesskit` dependency, an accessibility doc module and example. Its README states it is pre-1.0 with frequent breaking changes and requires latest stable Rust. Zed ships on Windows on it. [S19, S20]

Prior SwiftUI reimplementations set expectations. Tokamak, a SwiftUI-compatible framework for other renderers, was archived in January 2026 after covering a basic subset. OpenSwiftUI, the most complete independent implementation, still lists its cross-platform attribute graph as incomplete and text unsupported off Darwin, after years of work. Full SwiftUI parity is therefore scoped by inventory and oracle, never promised whole. [S7, S21]

SwiftCrossUI is a Swift SwiftUI-like runtime with a backend protocol and seven backends; its semantics are its own and it disclaims SwiftUI compatibility. Its WinUI backend sits on an archived binding lineage with an open UI Automation crash; v0.3 no longer depends on it. Its runtime core remains a candidate seed for SwiftRight's runtime, compared in SR0 against a fresh implementation. [S3, S4, S14, S15, S16]

Slint 1.17 is a stable, accessible, Rust-native toolkit with Windows x64 and arm64 support, moving to Fluent as default style everywhere. Its component language, lack of first-class Swift integration, and royalty-free licence terms for redistributable frameworks make it the second backend candidate, not the first. [S22, S23]

Swift–Rust interop has no official bridge. C ABI is supported by both languages; `swift-bridge` generates typed bindings over it. Either is work SwiftRight owns and tests. [S24]

An October 2026 spike shipped Swift 6.3 code as a `@c` DLL on Windows x64 and arm64 and established two reusable facts: Foundation ICU alone is ~37 MB, and Swift main-actor work only runs when the main dispatch queue is pumped from the host UI loop. [S18]

## 3. Architecture decisions

**AD1 — Unmodified toolchains.** Released Swift and Rust toolchains, Swift Package Manager, Cargo, supported platform SDKs. Pin a tested compatibility matrix.

**AD2 — One codebase, two implementations of SwiftUI's programming model.** On macOS, SwiftRight types are SwiftUI's types. On Windows, SwiftRight ships its own runtime implementing SwiftUI semantics (identity, state lifetime, dependency tracking, bindings, environment, layout proposals, transactions, lifecycle) and renders through a backend behind a narrow versioned C ABI. GPUI is the first backend; Slint is the second candidate behind the same backend protocol. Backends are swappable beneath the runtime without touching application code. A shell in another language or UI toolkit is never the fallback.

**AD3 — App-level state is portable; native objects are not.** Shared domain logic cannot depend on SwiftUI, AppKit, GPUI, React, or Tauri. Platform-owned UI state, focus, window handles, and renderer resources remain behind the relevant backend.

**AD4 — Existing engines survive.** Keep working Rust/C/C++ services. Add a versioned service boundary and replace the shell incrementally. On Windows the engine may link in-process with the renderer crate when that simplifies the app.

**AD5 — Parity is a tested contract with macOS as oracle.** Every API in the inventory has a compile fixture, a behavioural fixture recorded on macOS SwiftUI, and a Windows replay. Unsupported APIs fail at Windows compile time; nothing is a silent no-op.

**AD6 — Own the runtime, pin the renderer.** SwiftRight owns the Windows runtime, the bridge, control behaviour, accessibility mapping, services, conformance suite, and migration tooling. GPUI is consumed pinned, prebuilt, and isolated behind the bridge; upstream churn is absorbed in one crate, never in application code. Public API never leaks GPUI or Rust types.

**AD7 — Automation does labour, not judgment.** Agents regenerate fixtures from macOS runs, bump pinned renderers, rebuild prebuilt artifacts, extend inventory, triage CI. Humans decide semantics where SwiftUI is undocumented, accept behavioural specs, and approve contract changes. Nothing closed-source sits on the critical path.

**AD8 — No transpiler.** SwiftUI source is never converted to another toolkit's language. Swift compiles as Swift on both platforms.

## 4. Layered design

```text
Application
  Shared Swift domain logic and feature state
  Shared SwiftUI screen declarations
  Optional Mac-specific / Windows-specific feature modules
                        |
              SwiftRight public API (SwiftUI-compatible inventory)
           /                                   \
 macOS                                     Windows
 Apple SwiftUI + AppKit                    SwiftRight runtime (Swift)
 (typealiases, thin SwiftUI-view adapters)  identity, state, bindings, environment,
                                           layout, transactions, lifecycle, focus
                                                   |
                                           Backend protocol over versioned C ABI
                                                   |
                                           swiftright-render (Rust crate)
                                           GPUI elements, text, input, AccessKit
                                           Slint backend behind same protocol later
           \                                   /
           Platform service interfaces (Swift)
                        |
        Swift services / retained Rust engine (IPC or in-process)
                        |
          OS APIs and existing native runtimes
```

Cross-platform source compiles separately per platform. No SwiftUI view object crosses to Windows; no GPUI object crosses to macOS or into application code.

### Package boundaries

```text
swiftright/
  packages/
    SwiftRightCore/        # values, command contracts, capabilities, engine bridge contracts
    SwiftRightUI/          # public API; Mac target (SwiftUI) and Windows target (runtime + bridge client)
    SwiftRightServices/    # service contracts; Mac and Windows targets
    SwiftRightTesting/     # conformance fixtures, trace recorder (Mac), trace replayer (Windows)
  render/
    swiftright-render/     # Rust crate: backend protocol server, GPUI backend, AccessKit mapping
    swiftright-abi/        # C header + generated Swift/Rust bindings, versioned
  prebuilt/                # pinned renderer artifacts per OS/arch, reproducibly built
  scripts/                 # bundler, prebuilt artifact build, trace regen, CI matrix
  examples/
    ControlsGallery/
    DesktopUtility/
    EngineClient/
  conformance/
  benchmarks/
  docs/
```

Three Swift packages plus two Rust crates in v1. Split further only when a second consumer needs it.

## 5. SwiftUI on Mac, SwiftUI semantics on Windows

**macOS.** `SwiftRightUI.View`, `State`, `Binding`, `Environment`, and inventory modifiers are SwiftUI's own types. A thin adapter is allowed where it is itself a SwiftUI view and preserves composition and identity. Xcode previews, third-party SwiftUI packages, and the AppKit escape hatch stay intact. Consequence: every SwiftUI API compiles on Mac; only Windows compilation and conformance replay prove inventory membership.

**Windows.** The SwiftRight runtime implements SwiftUI's programming model, not its syntax alone:

- View identity: structural position plus explicit `id`, stable across insert, delete, filter, reorder.
- State lifetime: `@State` tied to identity; `@Binding` write-back and reentrancy; `@Environment` propagation and overrides; stdlib `Observation` dependency tracking.
- Layout: size proposals, measurement, alignment guides, placement, `Layout` protocol, `GeometryReader`, safe-area and scroll geometry.
- Transactions and animation: implicit and explicit animation, interruption, completion, reduced motion.
- Lifecycle: `onAppear`/`onDisappear`, `task` cancellation, preference keys, focus state.
- Text input: editing, selection, undo, IME composition, keyboard-only use.

The runtime produces a retained element tree and sends batched diffs across the bridge; the backend lays out, paints, and reports input, focus, and accessibility events back. Every control in the inventory has a backend implementation with Fluent-themed default styling and an AccessKit node mapping.

**Runtime seed.** SR0 compares two seeds on the decision slice: a fork of SwiftCrossUI's runtime core with a GPUI backend, and a fresh runtime written to SwiftUI semantics from the start. Choose by replay results and by how much SwiftCrossUI semantics must be rewritten.

**Rejected.** Wrapper-only on Mac (loses real SwiftUI at the type level). SwiftCrossUI as compatibility foundation (its semantics are its own; its WinUI backend chain is archived and crashes under UI Automation). Any SwiftUI-to-Slint/GPUI/Compose transpiler (no such tool exists; a compiler to maintain against every SwiftUI release; parity is semantics, not syntax). A C# WinUI or other second-language shell (breaks one codebase).

### Initial inventory

Text, buttons, toggles, single- and multi-line editable text, images, stacks, spacing, padding, alignment, scrolling, lists with selection and editing, menus, dialogs, one main window, keyboard actions, focus, basic animation. Each item ships with compile fixture, macOS trace, Windows replay, and accessibility assertions.

Expansion milestones: virtualization, tables, navigation, multiple windows, drag/drop, custom `Layout`, gestures. Document editors, canvas systems, and media timelines do not shape the first release.

### Compatibility categories

- **Inventory:** same source, same traced behaviour on both platforms.
- **Adapted:** same intent with a documented presentation difference (menu placement, control metrics, Fluent theming).
- **Platform extension:** intentionally Mac-only or Windows-only module.
- **Unsupported:** fails at Windows compile time.

## 6. State, identity, layout, events, threading

**Domain state.** Ordinary Swift values, explicit commands and effects, actors where isolation is required, stdlib `Observation` on both platforms, macOS 14 floor.

**Identity and lists.** Tests insert, delete, filter, and reorder rows while selection, caret, and IME composition are active. Losing the caret or binding an edit to the wrong row fails the build even when screenshots look right.

**Layout.** Portable sizing and alignment rules from SwiftUI's proposal model; font and control metrics may differ. Detect clipping, inaccessible hit targets, scrolling failures, and layout cost regressions.

**Events and tasks.** Specified ordering, cancellation, coalescing, and teardown. A closed window must not retain its element tree through an unbounded stream or engine callback.

**Threading and the bridge.** Rust owns the Windows event loop and GPU thread. Swift's main actor is pumped from that loop; the runtime verifies this in SR0 rather than assuming `@MainActor` suffices. Bridge rules: opaque handles, explicit ownership and free, batched diffs per frame, bounded queues, typed errors, panic containment on the Rust side, no closures across the ABI (callbacks go through handle plus event id). Measure bridge cost per event and per frame as a budget item.

## 7. Desktop shell is part of the SDK

| Interface | Required responsibilities |
|---|---|
| WindowService | Main/settings/utility windows, lifecycle, focus, geometry, close behavior, restoration |
| TrayService | Mac menu-bar item and Windows notification-area behavior, menus, commands |
| ShortcutService | App shortcuts, global hotkeys, conflicts, registration lifetime |
| ClipboardService | Read/write types, change observation where supported, sensitive-content policy |
| DialogService | File/folder selection, cancellation, filters, permissions |
| NotificationService | Permission state, posting, activation, errors |
| LaunchService | Open links/files, deep links, single-instance routing, launch-at-login |
| SecureStore | Minimal key/value credentials, availability, access-denied behavior |
| EngineService | Lifecycle, version negotiation, typed requests/events, cancellation |

Windows implementations are Swift over Win32/COM where simple, or delegated to the renderer crate where GPUI already owns the window. Updates are not an SDK service in v1: Sparkle on Mac, MSIX/winget on Windows. No generic shell-execution primitive.

Mac-specific features stay first-class through the Mac extension module. Core ML, Metal, and other Apple-specific components are not made portable by the UI layer; applications choose a Windows implementation behind the service contract.

## 8. Retaining Rust engines

Default migration path: Swift shell communicating with the existing Rust engine through a versioned local protocol over inherited pipes, user-restricted Unix socket, or user-restricted named pipe. Handshake, version range, request correlation, timeouts, bounded queues, typed errors, graceful shutdown, crash and reconnect.

On Windows, the engine may instead link into the same process as the renderer crate and expose the same versioned protocol in-process. Choose per app by measurement; keep the out-of-process path as rollback.

High-rate data (audio, frames, inference) stays inside the engine. Exchange commands, transcripts, status, and bounded progress with the UI. Never route raw frames through JSON.

In-process C ABI between Swift and Rust follows the bridge rules in §6: ownership, opaque handles, error values, thread rules, buffer lifetimes, panic containment.

## 9. Tooling and distribution

No bespoke CLI in v1. Swift Package Manager, Cargo, Swift Bundler, and repository scripts cover doctor/build/run/package/test. Xcode for Mac SwiftUI development and debugging; SourceKit-LSP on Windows.

**Prebuilt renderer.** The SDK ships pinned, reproducibly built `swiftright-render` artifacts per OS and architecture (Windows x64 and arm64) with recorded Rust toolchain and GPUI revision. Editing a Swift screen never rebuilds the Rust stack. Each arch builds on its own runner.

**Pinned tuple.** Swift toolchain, Rust toolchain, Mac SDK/Xcode, Windows SDK, GPUI revision, AccessKit revision, bridge ABI version, SwiftRight version, engine protocol version.

**Packaging.** Mac: app bundle, resources, entitlements, signing, notarization. Windows: MSIX or sparse package for identity, Swift runtime redistribution (static stdlib or side-by-side manifests as those reach swift.org builds), signing, winget. Swift Bundler covers generic directory and WiX MSI; MSIX is scripted. Clean-VM install, uninstall, upgrade, failed update, and first-launch permission tests on both OSes.

## 10. First consumers and migration

Begin with a real desktop utility/settings screen: persistent state, editable text, a list, tray entry, shortcut, dialog, releasable package.

For HeardRight-like functionality: settings or command history against the existing engine first, then resident/tray behaviour, then overlay/audio workflows.

Keep the current app functional while adding the new shell behind a development/release option. Preserve file formats and IPC semantics. Migrate one complete feature at a time. React/TypeScript screens are rewritten once into SwiftUI; thereafter one source serves both platforms.

RustRight's CLI must not depend on this SDK; the SDK must not require RustRight to build.

## 11. Conformance and performance

Three test layers: inventory contract tests, platform interaction tests, complete application tests.

**Oracle.** Each fixture runs on macOS SwiftUI under instrumentation that records state transitions, focus, accessibility tree, and layout frames into a trace. Windows replays the fixture and diffs against the trace within documented tolerances. Divergence is a runtime bug or an explicit "adapted" entry, never silent.

Cover state and binding lifecycle, focus, undo/redo, Unicode and IME, keyboard-only use, accessibility roles/labels/actions through UI Automation on Windows and the accessibility API on macOS, right-to-left, high contrast, reduced motion, DPI scaling, multi-monitor, window reopen, subscription teardown.

**Windows accessibility gate.** A UI Automation walk of every shipped window completes and exposes every control; Narrator and NVDA activate inventory controls. Screen-reader failure is a release blocker.

**Budgets per OS.** Baselines from release builds of the same feature and engine on the same hardware, including the current React/Tauri shell. Expect Mac to win clearly against WebView. On Windows, measure rather than assume: GPUI is GPU-accelerated and WebView2 is preinstalled, Swift adds Foundation ICU (~37 MB) and the Rust renderer. Budget startup-to-interactive, working set, process-tree memory, input latency, bridge cost per event and per frame, scrolling frame pacing, CPU wakeups, package size, UI-only build time.

## 12. Delivery gates

**SR0 — Decision slice. Time box: eight weeks.** One feature through Apple SwiftUI and the Windows candidate: an editable, reorderable list with an async insert above the row being edited; a custom `Layout`; an interrupted animation; an async update with cancellation; keyboard and IME editing; accessibility inspection and activation. Deliverables in order:

1. Bridge ABI v0 and `swiftright-render` with GPUI backend, prebuilt for Windows x64 and arm64.
2. Main-actor pumping from the Rust loop verified under load.
3. Two runtime seeds (SwiftCrossUI core fork, fresh) driving the slice; pick one by trace replay.
4. macOS trace recorder and Windows replayer running the slice in CI.
5. UI Automation walk of the slice window completes; Narrator activates list, text field, button.
6. Clean-VM install on both OSes with signed Mac bundle and MSIX on Windows.
7. Automation jobs live: trace regen, renderer pin bump with prebuilt rebuild, toolchain matrix, Windows CI with UIA gate.

Kill criteria at week eight: bridge cost exceeds budget after batching; chosen seed cannot pass list-identity or IME replay; AccessKit mapping cannot satisfy the UIA gate. Any one triggers plan B.

Plan B stays inside one codebase: swap the backend beneath the same runtime and bridge protocol to Slint, after written licensing clarification for a redistributable framework. Runtime, facade, and application code do not change.

**SR1 — Inventory contract.** Initial inventory with fixtures, traces, replays. Unsupported APIs fail at Windows compile. List identity, binding, focus, cancellation, teardown pass before adding controls.

**SR2 — Desktop utility.** Complete internal utility with persistence, menus/tray, shortcuts, dialogs, installer per OS. Error paths verified.

**SR3 — Engine-backed feature.** One real feature through the shell against an existing engine, in-process on Windows if measured better. Tests cover crash, restart, incompatible protocol, cancellation, stale events, rollback.

**SR4 — Production performance and reliability.** Budgets met, clean-machine install and update, platform differences documented. A Mac regression blocks release even when Windows passes.

**SR5 — Community release.** Second independent application, inventory tables, pinning guidance, escape-hatch examples, issue templates, backend ownership.

Parallel workstreams after SR0: Mac adapters, Windows runtime, renderer crate, services, conformance, packaging/CI. One state, event, and error protocol across all streams.

Each agent task specifies API contract, platform, fixture, expected failures, ownership, and evidence to merge. One model implements while another builds adversarial tests; both execute through real compilers and platform tests. Agreement between models is not validation. An agent cannot remove a failing conformance test, relax an inventory claim, or substitute a browser surface. A maintainer approves contract changes.

## 13. Long-term maintenance

Platform owners and a release manager. Automation owns trace regeneration on SwiftUI releases, renderer pin bumps, prebuilt rebuilds, toolchain matrix, CI triage. Humans own semantics where SwiftUI is undocumented, spec acceptance, contract approval. Budget Windows x64 and arm64 runners, Mac runners, signing certificates, clean VMs as infrastructure cost separate from inference.

Stable pinned lane and candidate lane. GPUI breaking changes land in the candidate lane behind the bridge; application code is unaffected by design. Track provenance and licence for every reused component from the Zed repository individually; only `gpui` itself is assumed Apache-2.0.

Inventory grows by consumer demand and recorded traces. Broader SwiftUI coverage, more platforms, and alternative backends are expansion projects, not reasons to defer the first useful utility.

Keep the product usable after the AI entitlement ends: no unlimited inference, no free build infrastructure, no auto-verified code.

## References

Public documentation and source inspected on 8 October 2026.

[S1] Swift platform support: `https://www.swift.org/platform-support/`

[S2] Swift on Windows installation: `https://www.swift.org/install/windows/`

[S3] SwiftCrossUI README: `https://github.com/moreSwift/swift-cross-ui`

[S4] SwiftCrossUI Package.swift: `https://github.com/moreSwift/swift-cross-ui/blob/main/Package.swift`

[S5] Apple SwiftUI: `https://developer.apple.com/swiftui/`

[S6] Microsoft WinUI 3: `https://learn.microsoft.com/en-us/windows/apps/winui/winui3/`

[S7] OpenSwiftUI: `https://github.com/OpenSwiftUIProject/OpenSwiftUI`

[S8] Swift Bundler: `https://github.com/moreSwift/swift-bundler`

[S9] SwiftCrossUI LLM policy: `https://github.com/moreSwift/swift-cross-ui/blob/main/LLM_POLICY.md`

[S10] Swift Windows Workgroup: `https://swift.org/blog/announcing-windows-workgroup/`

[S11] What's new in Swift, March 2026: `https://swift.org/blog/whats-new-in-swift-march-2026/`

[S12] Browser Company, Swift on Windows year of refinement: `https://speakinginswift.substack.com/p/swift-on-windows-a-year-of-refinement`

[S13] Browser Company, symbol server and hiring: `https://speakinginswift.substack.com/p/a-public-symbol-server-for-swift`

[S14] `thebrowsercompany/swift-winui`, archived: `https://github.com/thebrowsercompany/swift-winui`

[S15] `swift-winrt` issue #263: `https://github.com/thebrowsercompany/swift-winrt/issues/263`

[S16] SwiftCrossUI issue #787: `https://github.com/moreSwift/swift-cross-ui/issues/787`

[S17] Skip open-sourced, iOS and Android only: `https://www.infoq.com/news/2026/01/swift-skip-open-sourced`

[S18] ClaudeBar-Windows issue #2, Swift DLL spike: `https://github.com/tddworks/ClaudeBar-Windows/issues/2`

[S19] GPUI crate README and Cargo.toml (`accesskit`, Apache-2.0, pre-1.0): `https://github.com/zed-industries/zed/tree/main/crates/gpui`

[S20] GPUI site: `https://gpui.rs`

[S21] Tokamak, archived January 2026: `https://github.com/TokamakUI/Tokamak`

[S22] Slint default style change to Fluent: `https://slint.dev/blog/default-native-style-change`

[S23] Slint changelog (1.15–1.17, native handles, accessibility): `https://github.com/slint-ui/slint/blob/master/CHANGELOG.md`

[S24] swift-bridge, Swift–Rust FFI generator: `https://github.com/chinedufn/swift-bridge`
