# SwiftRight: shared Swift applications, native Mac and Windows

Architecture v0.2 — 8 October 2026  
Status: proposed architecture; no implementation or measured performance claimed. v0.2 incorporates the adversarial review in `architecture-review.md`: verified dependency state, facade decision, SR0 time box with kill criteria, reduced v1 scope, automation posture.

## 1. Product definition

Build a maintained desktop application SDK, not a Swift compiler fork and not an emulator for macOS binaries.

The target is **shared Swift application logic and shared source for a tested portable UI surface, rendered through real SwiftUI/AppKit on macOS and native WinUI on Windows, with platform extensions where they improve the application.** Existing Rust engines remain reusable. A UI-only change should not require rebuilding an unchanged Rust engine.

One UI codebase is a hard requirement. Two hand-maintained shells, or a transitional third, is the outcome this project exists to avoid. The user currently chooses React/Tauri for portability but prefers Swift's Mac experience. Therefore “native on Mac” is not enough as an abstract label: the Mac backend must preserve actual SwiftUI integration and a direct AppKit escape hatch. The Windows implementation should feel like a well-built Windows application, not imitate every macOS visual convention.

AI is used to help develop and test the SDK. Shipped applications must not require Claude, GPT, a network connection, or an AI subscription just to render UI or call platform services.

## 2. Verified starting points

Swift's official platform documentation supports development and deployment on Windows, with x86_64 and arm64 toolchains, WinGet installation, and container images. A Swift Windows Workgroup exists since January 2026. Swift Build is landing as the cross-platform default build system. The project therefore starts above the language/compiler port. [S1, S2, S10, S11]

The Browser Company continues to publish Windows toolchain builds, a public symbol server, static-stdlib and side-by-side runtime work, and was hiring Swift-on-Windows engineers as of May 2026. Its WinRT generator `swift-winrt` is active. Its prebuilt binding snapshot `swift-winui` is archived (October 2025), pinned to Windows App SDK 1.7, x64 only, and self-described as an outdated illustration. Its binding-generation scripts fail on Windows App SDK 1.8's NuGet layout; that issue has been open without reply since May 2026. [S12, S13, S14, S15]

SwiftCrossUI has an AppKit backend on macOS and a WinUI backend on Windows; it explicitly does not promise SwiftUI API compatibility. Verified state of its Windows backend on 8 October 2026: [S3, S4, S16]

| Item | State |
|---|---|
| Dependency | single package `moreSwift/swift-winui`, `.upToNextMinor(from: "0.2.2")`, a fork of the archived snapshot |
| Windows App SDK runtime in use | 1.5 line |
| Architectures | x64 only |
| Windows test target | none |
| Hot reload | hard-disabled on Windows |
| Accessibility | issue #787: UI Automation walk (any screen reader) crashes app when window contains List, ScrollView, TextField, NavigationSplitView; simpler windows expose one UIA element. Suspected upstream `Microsoft.UI.Xaml.dll` bug. No maintainer response. |
| Manifest tools version | 5.10; Swift 6 strict concurrency at boundary needs work |
| Observation | `swift-observation-polyfill`, not stdlib `Observation` |

Conclusion: SwiftCrossUI's WinUI backend is a starting point this project owns and repairs, not infrastructure it consumes. Windows App SDK projections for a supported SDK line, arm64, accessibility, and tests are SwiftRight work.

Apple's SwiftUI is the Mac rendering foundation. WinUI 3 is the native Windows control foundation. Apple's cross-platform investment is in language and toolchain, not UI; SwiftUI remains Apple-only. Treat source-level similarity, behavioural equivalence, native appearance, and performance as separately testable properties. [S5, S6]

OpenSwiftUI is a research reference only; its README lists Windows unsupported and warns about private Apple-framework dependencies. Skip targets Android, not Windows. No SwiftUI-to-other-toolkit transpiler exists; building one is rejected (§5). [S7, S17]

An independent October 2026 spike shipped Swift 6.3 domain code as a `@c` DLL under a C# WinUI 3 shell on Windows App SDK 2.5, x64 and arm64, MSIX, NativeAOT. It establishes current Swift-on-Windows facts this design reuses: Foundation ICU alone is ~37 MB, Swift main-actor work needs the main dispatch queue pumped from the WinUI dispatcher, and each architecture builds on its own runner. It is not a shell option here; a second-language shell violates §1. [S18]

## 3. Architecture decisions

**AD1 — Unmodified toolchains.** Use released Swift toolchains, Swift Package Manager, and supported platform SDKs. Pin a tested compatibility matrix rather than requiring the newest version immediately.

**AD2 — One UI codebase, two compile-time implementations.** Implement the portable public surface against SwiftUI on macOS and a WinUI backend on Windows, initially SwiftCrossUI's. The Windows backend is replaceable beneath the facade (own thin WinUI binding, or Win32) without touching application code. A shell in another language or toolkit is never the fallback. There is no JavaScript engine or browser-view requirement for ordinary SDK controls, and no generic JSON UI interpreter in the default path.

**AD3 — App-level state is portable; native objects are not.** Shared domain logic cannot depend on SwiftUI, AppKit, WinUI, React, or Tauri. Platform-owned UI state, focus, window handles, and COM objects remain behind the relevant backend.

**AD4 — Existing engines survive.** Keep working Rust/C/C++ services. Add a versioned service boundary and replace the shell incrementally. Do not rewrite an engine simply to make the repository appear all-Swift.

**AD5 — Portability is a tested contract.** The public SDK specifies supported APIs and behaviours. Broader SwiftUI source compatibility is earned by adding fixtures, not by making unsupported methods silent no-ops.

**AD6 — Own the Windows chain, upstream where accepted.** SwiftRight owns: the portable facade, Mac SwiftUI implementation, regenerated Windows App SDK projections (supported SDK line, x64 and arm64), a SwiftCrossUI fork with Windows fixes, shell services, conformance suite, migration tooling. Keep framework-independent fixes upstreamable under SwiftCrossUI's LLM policy, which requires human-written issues and pull requests; autonomous upstreaming is not available, so the fork is permanent and bot-rebased.

**AD7 — Automation does labour, not judgment.** Agents regenerate projections, rebase forks, bump toolchains, extend fixtures, triage CI. Humans decide facade semantics, accept behavioural specs, approve contract changes, and handle closed-source upstream bugs that no agent can patch. Kill criteria exist for that last class.

## 4. Layered design

```text
Application
  Shared Swift domain logic and feature state
  Shared portable screen declarations
  Optional Mac-specific / Windows-specific feature modules
                        |
              SwiftRight public API
           /                           \
 macOS implementation             Windows implementation
 SwiftUI + AppKit                 SwiftCrossUI WinUI backend
                                  + pinned swift-winui projection
           \                           /
           Platform service interfaces
                        |
        Swift services / retained Rust engine
                        |
          OS APIs and existing native runtimes
```

Cross-platform source is compiled separately for each platform. No compiled SwiftUI view object crosses into Windows, and no Windows UI object crosses into macOS. Separate binaries and platform packaging are expected outputs of one source project.

### Package boundaries

```text
swiftright/
  packages/
    SwiftRightCore/          # values, command contracts, capabilities, engine bridge contracts
    SwiftRightUI/            # portable UI API; Mac and Windows implementations as targets
    SwiftRightServices/      # service contracts plus Mac and Windows targets
    SwiftRightTesting/       # conformance fixtures and event traces
  windows-projections/       # regenerated Windows App SDK bindings, committed, reproducible
  scripts/                   # bundler, projection regen, CI matrix; no bespoke CLI in v1
  examples/
    ControlsGallery/
    DesktopUtility/
    EngineClient/
  conformance/
  benchmarks/
  docs/
    compatibility.md
    dependency-matrix.md
    architecture-decisions/
```

This is a proposed modular structure, not a claim that these packages exist. Three packages plus per-platform targets in v1; split further only when a second consumer needs it. Keep executable app entry points platform-specific while sharing domain and screen modules.

## 5. Shared UI without sacrificing real SwiftUI

Use an intentionally scoped facade. On macOS, supported facade types and modifiers become SwiftUI types/adapters; on Windows, they become equivalent supported declarations/adapters over SwiftCrossUI and WinUI. Native extension views can be embedded through explicit platform entry points.

A conditional import alone does not solve compatibility. The implementation must reconcile protocol conformance, result-builder output, modifiers, property wrappers, generic view types, environment values, and observation lifetimes. That reconciliation is a central workstream.

**Decision: typealias on Mac.** On macOS, `SwiftRightUI.View`, `State`, `Binding`, and supported modifiers are SwiftUI's own types. Xcode previews, third-party SwiftUI packages, and the AppKit escape hatch stay intact. Consequence: every SwiftUI API compiles on Mac, and only Windows compilation proves portability. Therefore **Windows compilation in CI is the compatibility lint**; no separate diagnostics tool in v1. A screen that compiles on Mac and not on Windows is unsupported until a fixture and Windows adapter exist. Wrapper-on-both is rejected: it makes Mac not real SwiftUI at the type level, contradicting §1.

Do not depend on underscored Swift re-export mechanisms or private SwiftUI APIs as the public contract. Avoid blanket type erasure that hides identity or prevents efficient updates. Prove this facade with a small vertical slice in SR0 before multiplying its surface area.

Source-to-source conversion of SwiftUI into another toolkit (Slint, GPUI, Compose-style) is rejected. No such tool exists; it adds a compiler to maintain against every SwiftUI release; parity between a native toolkit and a self-rendering toolkit is semantic equivalence, not translation.

The desired source shape is shown below only as an API sketch; it has not been compiled and is not an existing SDK:

```swift
import SwiftRightUI

struct SettingsScreen: View {
    @Binding var launchAtLogin: Bool

    var body: some View {
        VStack {
            Text("Settings")
            Toggle("Launch at login", isOn: $launchAtLogin)
        }
        .padding()
    }
}
```

The toggle edits feature state. A separate application command asks the platform service to change launch-at-login registration and publishes success/failure. The visual binding must not silently claim that the OS operation succeeded.

### Initial portable surface

The first scope should cover a genuine desktop utility: text, buttons, toggles, single-line editable text, images, basic stacks, spacing, padding, alignment, scrolling, selection, menus, dialogs, one main window, and keyboard actions. State updates and focus behavior are part of each control, not a later decorative feature.

Add virtualization, richer tables, navigation, multiple windows, drag/drop, and animation as tested expansion milestones. Large document editors, advanced canvas/rendering systems, and specialized media timelines should not determine the first release's architecture.

The facade is not intended to remain permanently small. Expand it based on actual application coverage and community demand. The acceptance standard is a compile fixture plus behavioural tests plus platform tests for every claimed API.

### Compatibility categories

Publish separate labels for each API:

- **Portable:** same supported source and specified behaviour on both platforms.
- **Adapted:** same intent with a documented platform-specific presentation or interaction.
- **Platform extension:** intentionally available only in a Mac or Windows module.
- **Unsupported:** diagnosed explicitly rather than rendered incorrectly or ignored.

Source support and runtime capability differ. Static unsupported APIs fail at Windows compile time. Runtime capabilities such as notification permission need typed availability/denial results and a fallback path.

## 6. State, identity, layout, and events

**Domain state.** Model feature state as ordinary Swift values and explicit commands/effects. Use actors where concurrency requires isolation. Shared services publish versioned state snapshots or bounded event streams. Use stdlib `Observation`, which ships in Swift 6 toolchains on Windows; set a macOS 14 floor. SwiftCrossUI's observation polyfill exists for macOS 10.15 back-deploy and conflicts with this; resolve by upstream flag or in the owned fork during SR0.

**View-local state.** The facade's state and binding adapters preserve lifecycle on each backend. Shared feature state does not imply that the two platforms share one physical observation engine. Bindings must have tested ownership, writeback, reentrancy, and destruction semantics.

**Identity.** Define stable identity for repeated elements. Add tests where rows are inserted, deleted, filtered, and reordered while selection or text editing is active. A visual list that loses the caret or binds an edit to the wrong row is a failed implementation even when the screenshot looks correct.

**Layout.** Use documented portable sizing/alignment rules while allowing native font/control metrics to differ. Do not require pixel-identical Mac/Windows screenshots. Detect clipping, inaccessible hit targets, scrolling failures, and unreasonable layout costs.

**Events and tasks.** Specify event ordering, cancellation, event coalescing, and subscription teardown. A closed window must not retain its view graph through an unbounded event stream or engine callback.

**Threading.** Shared actors exchange values, not native UI handles. WinUI objects must stay on their owning UI dispatcher; Mac UI work stays on the platform UI thread. The bootstrap spike must establish the relationship between Swift concurrency execution and the WinUI dispatcher rather than assume that annotating a type `@MainActor` completes integration. Known hazard: `RunLoop.main` does not drain Swift's main dispatch queue on Windows; the October 2026 spike pumped it from a DispatcherQueue timer. Verify SwiftCrossUI's WinUI backend answer in SR0. [S18] Do not paper over thread-affinity issues with broad unchecked Sendable conformance.

## 7. The desktop shell is part of the SDK

React/Tauri replacement requires more than controls. Define platform-independent interfaces for the services below, with native implementations and explicit capability/error reporting.

| Interface | Required responsibilities |
|---|---|
| WindowService | Main/settings/utility windows, lifecycle, focus, geometry, close behavior, restoration |
| TrayService | Mac menu-bar item and Windows notification-area behavior, menus, commands |
| ShortcutService | App shortcuts, global hotkeys, conflicts, registration lifetime |
| ClipboardService | Read/write types, change observation where supported, sensitive-content policy |
| DialogService | File/folder selection, cancellation, filters, permissions |
| NotificationService | Permission state, posting, activation, errors |
| LaunchService | Open links/files, deep links, single-instance routing, launch-at-login |
| SecureStore | Key/value credentials, availability, recovery and access-denied behavior |
| EngineService | Lifecycle, version negotiation, typed requests/events, cancellation |

Updates are not an SDK service in v1: Sparkle on Mac, MSIX/winget on Windows. SecureStore is minimal key/value in v1. Platform-specific code belongs behind these boundaries rather than scattered through every screen. Do not expose a generic unrestricted shell-execution primitive as a convenience replacement for explicit services.

Mac-specific features remain first-class through the Mac extension package. Windows-specific shell and accessibility integration remains equally possible. Cross-platform does not require the least capable common denominator.

Media capture, accessibility automation, model inference, and hardware acceleration are separate optional service packages. Existing native or Rust implementations are preferred where already functional. Core ML, Metal, and other Apple-specific components are not made portable by importing a UI facade; the application chooses an appropriate Windows implementation behind the service contract.

## 8. Retaining Rust engines

The default migration path is a Swift native shell communicating with the existing Rust engine through a versioned local protocol. Where an app already has a sidecar boundary, preserve and formalize it. Where Tauri commands directly own business logic, extract an engine-facing service interface before replacing the UI.

Start with inherited pipes, a user-restricted Unix socket, or a user-restricted Windows named pipe, chosen per platform and threat model. Avoid an unauthenticated localhost HTTP service. Require a protocol handshake and a supported version range.

A proposed message envelope contains protocol version, request ID, message kind, payload type/version, and cancellation metadata. Include request/response correlation, timeouts, bounded queues, typed errors, graceful shutdown, and crash/reconnect behavior. Generate language bindings from a versioned schema when practical, while keeping generated output deterministic and reviewable.

For audio, capture, or inference, keep high-rate data inside the engine when possible. Exchange commands, transcripts, status, and bounded progress updates with the UI. Do not route raw frames through JSON simply because a control-message channel exists.

Use an in-process C ABI only where measurements justify it. That ABI needs explicit ownership/freeing rules, opaque handles, error values, thread rules, buffer lifetimes, and panic containment. Never assume that Rust's native ABI or memory layouts can be called directly from Swift safely.

This choice keeps UI iteration independent from the engine build. It also preserves a rollback route while migrating away from the old shell.

## 9. Tooling and distribution

No bespoke CLI in v1. Swift Package Manager, Swift Bundler, and repository scripts cover doctor/build/run/package/test. A CLI is earned once a second consumer repeats the same scripts.

Use Swift Package Manager for shared code. Keep Xcode integration for real SwiftUI development and debugging on Mac. Provide SourceKit-LSP/editor integration on Windows. Swift Bundler produces a generic directory or WiX MSI on Windows; it has no MSIX output. Windows App SDK features such as notifications want package identity, so SR0 decides MSIX or sparse package and scripts it. Swift runtime redistribution on Windows follows the static-stdlib or side-by-side manifest route from the Browser Company toolchain work as it reaches swift.org builds. [S2, S8, S12]

Resolve and pin the complete build tuple: Swift toolchain, Mac SDK/Xcode or Windows SDK/Windows App SDK, WinUI projection revision and generator version, SwiftCrossUI fork revision, Windows architectures (x64 and arm64), SwiftRight version, and any engine ABI/protocol version. The current upstream package ranges are evidence of dependencies, not the project's future compatibility promise.

Use platform-native CI runners for initial builds. Do not make cross-compiling and signing everything from a single host a prerequisite. Include clean end-user environments without a developer toolchain, install/uninstall, upgrade, failed update, resource loading, DLL/runtime discovery, and first-launch permission behavior.

Mac packaging includes the correct app bundle, resources, entitlements, signing, and applicable notarization workflow. Windows packaging includes required runtime deployment, app identity/manifest choices, signing and installer/update behavior. A window that launches only on the development machine is not a completed platform port.

The SDK ships prebuilt, reproducibly generated Windows App SDK projections for a supported SDK line, x64 and arm64, with recorded generator and SDK versions. This is SR0's first deliverable: nothing else on Windows runs without it, and the archived upstream snapshot cannot be used. Regeneration on SDK bumps is an automated job. Keep generated bindings separate from hand-authored runtime adapters.

## 10. First consumers and migration

Begin with a real desktop utility/settings screen that exercises persistent state, editable text, a list, a tray/menu entry, a shortcut, a dialog, and a releasable package. This is more informative than a counter demo but avoids starting with the most specialized application surface.

For HeardRight-like functionality, a useful first feature slice is settings or command history against an existing engine, followed by resident/tray behavior and then more specialized overlay/audio workflows. This is a proposed migration sequence, not an assertion about the current repository's exact component boundaries.

Keep the current app functional while adding the new shell behind an explicit development/release option. Preserve file formats and IPC semantics where possible. Migrate one complete feature at a time; do not leave two independently evolving implementations of the same business logic.

React/TypeScript UI is a one-time rewrite into the portable Swift API. It is not automatically recompiled as Swift. Existing tested engine behavior and platform code are reuse opportunities. Once the Swift screen exists, supported future UI source is shared across Mac and Windows.

A later RustRight dashboard can serve as a second independent consumer. RustRight's CLI must not depend on this SDK, and the SDK must not require RustRight to build. Their releases and correctness boundaries remain independent.

## 11. Conformance and performance

Maintain three test layers: portable API contract tests, platform interaction tests, and complete application tests. An API is not “supported” merely because an AI-generated wrapper compiles.

Test state/binding lifecycle, focus, undo/redo, Unicode and input-method composition, keyboard-only use, accessibility roles/labels/actions, right-to-left layouts, high contrast, reduced motion, DPI scaling, multi-monitor movement, window reopen, and subscription teardown.

Use screenshots for visual regressions within each platform, and event/accessibility assertions for cross-platform behavioural compatibility. OS-native differences such as menu placement or control metrics are expected when documented.

Set numeric budgets from a baseline measurement, not from language reputation. Compare release builds of the same feature and engine on the same hardware: startup-to-interactive, idle and active working set, total process-tree memory, input latency, long-list scrolling/frame pacing, CPU wakeups, package size, UI-only build time, and framework-induced rebuilds. Include the current React/Tauri implementation and a small direct-native baseline.

Measure the bridge and framework overhead separately from engine/model memory. Replacing a WebView does not imply the same percentage reduction for an app whose resident model dominates memory.

Set budgets per OS. Expect Mac to win clearly against WebView. Expect Windows package size to be neutral or worse: WebView2 is preinstalled, while Swift brings Foundation ICU (~37 MB) plus the Windows App SDK runtime. Do not let a Windows size regression block release if Windows memory, latency, and startup meet budget. [S18]

Windows accessibility is a release gate: a UI Automation walk of every shipped window must complete and expose the control tree. A screen-reader crash is an application crash.

## 12. Delivery gates and parallel work

**SR0 — Backend viability and pinned tuple. Time box: six weeks.** Deliverables in order:

1. Regenerated Windows App SDK projections for a supported SDK line, x64 and arm64, committed with reproducible regen script.
2. SwiftCrossUI fork building against those projections with stdlib `Observation`.
3. Facade vertical slice (typealias on Mac) rendering one screen with text, toggle, editable text, and a list on both OSes; Windows compile as lint.
4. UI Automation walk of that screen on Windows completes without crash and exposes every control.
5. Main-actor and WinUI dispatcher relationship verified under load.
6. Clean-VM install on both OSes: signed Mac bundle; MSIX or sparse package on Windows with runtime redistribution.
7. Automation jobs live: projection regen, fork rebase, toolchain matrix, Windows CI with UIA gate.

Kill criteria, evaluated at week six: UIA crash cannot be avoided in the owned backend; projections cannot regenerate for a supported SDK line; facade needs wrappers on Mac. Any one triggers plan B.

Plan B stays inside the one codebase: replace the Windows backend beneath the facade with an owned thin WinUI binding over the same projections, or a Win32 backend. Application and facade code do not change. A second-language or second-toolkit shell is not plan B.

**SR1 — Executable compatibility contract.** Implement the initial UI surface with compile fixtures and behavioural tests. Unsupported APIs fail explicitly. Pass list-identity, binding, focus, cancellation, and teardown tests before expanding control count.

**SR2 — Desktop utility.** Ship a complete internal utility with persistence, menus/tray, shortcuts, dialogs, and an installer/package for each OS. Verify platform capabilities and error paths, not only happy paths.

**SR3 — Engine-backed feature migration.** One real feature runs through the native shell against an existing engine. Tests cover engine crash, restart, incompatible protocol, cancellation, stale events, and rollback to the existing application version.

**SR4 — Production performance and reliability.** Meet measured product budgets, pass clean-machine installation/update tests, and document remaining platform differences. A regression in the critical Mac experience blocks release even if Windows works.

**SR5 — Community release.** Support a second independent application, publish compatibility tables, pinning/upgrade guidance, native escape-hatch examples, issue templates with reproductions, and maintainer ownership for each backend.

Parallel workstreams after SR0's interfaces stabilize are: Mac facade, Windows facade/interop, service layer, independent conformance tests, and packaging/CI. Do not allow each stream to invent its own state, event, or error protocol.

Each agent task specifies an API contract, target platform, fixture, expected failures, source ownership, and evidence required to merge. One model may implement while another builds adversarial tests; both must execute through real compilers and platform tests. Agreement between models is not validation.

Keep source changes and test changes reviewable. An implementation agent cannot silently remove a failing conformance test, relax compatibility claims, or replace native controls with a browser surface to finish a task. A maintainer approves contract changes.

## 13. Long-term maintenance and scope expansion

Define platform owners and a release manager. Automation owns routine maintenance: projection regeneration on Windows App SDK releases, SwiftCrossUI fork rebases, toolchain matrix bumps, fixture extension on SwiftUI releases, CI triage. Humans own facade semantics, behavioural specs, contract approval, and closed-source upstream bugs. Budget Windows and arm64 runners, signing certificates, and clean VMs as infrastructure cost, separate from inference. Maintain a stable pinned lane and a candidate-update lane. Add an upstream change only after conformance, packaging, and representative application tests pass. Publish explicit deprecations rather than chasing every new Apple API immediately.

Treat generated interop bindings as a reproducible supply-chain component with recorded generator and SDK versions. Track upstream patches and license provenance before copying code. Keep private Apple frameworks out of the shipping dependency graph.

Source compatibility can grow in a dedicated module once the core works. Broader SwiftUI API support, additional native services, more platforms, and specialized rendering backends are expansion projects, not reasons to defer the initial useful desktop SDK.

Community adoption is supported by real examples, predictable releases, testable contribution boundaries, and reproducible failures. Upstream projects can impose their own AI contribution policies; SwiftCrossUI currently documents conditions for AI-assisted code and human-written issue/pull-request descriptions. Follow those when contributing upstream. [S9]

The user's year of Claude access is an opportunity to front-load implementation and test construction. Keep the product and maintenance process usable after that entitlement ends; it does not imply unlimited inference, free build infrastructure, or automatically verified code.

## References

Public documentation/source inspected on 8 October 2026. References support upstream facts; the architecture and interfaces above are proposals.

[S1] Swift platform support: `https://www.swift.org/platform-support/`

[S2] Swift on Windows installation and developer tooling: `https://www.swift.org/install/windows/`

[S3] SwiftCrossUI README, backends, and compatibility scope: `https://github.com/moreSwift/swift-cross-ui`

[S4] SwiftCrossUI package manifest and WinUI backend dependencies: `https://github.com/moreSwift/swift-cross-ui/blob/main/Package.swift`

[S5] Apple SwiftUI overview: `https://developer.apple.com/swiftui/`

[S6] Microsoft WinUI 3 overview: `https://learn.microsoft.com/en-us/windows/apps/winui/winui3/`

[S7] OpenSwiftUI support matrix and private-framework warning: `https://github.com/OpenSwiftUIProject/OpenSwiftUI`

[S8] Swift Bundler: `https://github.com/moreSwift/swift-bundler`

[S9] SwiftCrossUI AI contribution policy: `https://github.com/moreSwift/swift-cross-ui/blob/main/LLM_POLICY.md`

[S10] Swift Windows Workgroup announcement, January 2026: `https://swift.org/blog/announcing-windows-workgroup/`

[S11] What's new in Swift, March 2026 (Swift Build across Linux and Windows): `https://swift.org/blog/whats-new-in-swift-march-2026/`

[S12] The Browser Company, Swift on Windows: a year of refinement, July 2026: `https://speakinginswift.substack.com/p/swift-on-windows-a-year-of-refinement`

[S13] The Browser Company, public symbol server and hiring, May 2026: `https://speakinginswift.substack.com/p/a-public-symbol-server-for-swift`

[S14] `thebrowsercompany/swift-winui`, archived October 2025: `https://github.com/thebrowsercompany/swift-winui`

[S15] `swift-winrt` issue #263, Windows App SDK 1.8 layout: `https://github.com/thebrowsercompany/swift-winrt/issues/263`

[S16] SwiftCrossUI issue #787, WinUI backend UI Automation crash: `https://github.com/moreSwift/swift-cross-ui/issues/787`

[S17] Skip open-sourced, January 2026 (iOS and Android only): `https://www.infoq.com/news/2026/01/swift-skip-open-sourced`

[S18] ClaudeBar-Windows issue #2, Swift DLL under C# WinUI 3 spike, October 2026: `https://github.com/tddworks/ClaudeBar-Windows/issues/2`
