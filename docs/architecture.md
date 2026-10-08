# SwiftRight: shared Swift applications, native Mac and Windows

Architecture v0.1 — 8 October 2026  
Status: proposed architecture; no implementation or measured performance claimed.

## 1. Product definition

Build a maintained desktop application SDK, not a Swift compiler fork and not an emulator for macOS binaries.

The target is **shared Swift application logic and shared source for a tested portable UI surface, rendered through real SwiftUI/AppKit on macOS and native WinUI on Windows, with platform extensions where they improve the application.** Existing Rust engines remain reusable. A UI-only change should not require rebuilding an unchanged Rust engine.

The user currently chooses React/Tauri for portability but prefers Swift's Mac experience. Therefore “native on Mac” is not enough as an abstract label: the Mac backend must preserve actual SwiftUI integration and a direct AppKit escape hatch. The Windows implementation should feel like a well-built Windows application, not imitate every macOS visual convention.

AI is used to help develop and test the SDK. Shipped applications must not require Claude, GPT, a network connection, or an AI subscription just to render UI or call platform services.

## 2. Verified starting points

Swift's official platform documentation supports development and deployment on Windows. The official installation path also documents Windows SDK and Visual Studio tooling dependencies. The project therefore starts above the language/compiler port. [S1, S2]

SwiftCrossUI has an AppKit backend on macOS and a WinUI backend on Windows; it explicitly does not promise perfect SwiftUI API compatibility. Its inspected package manifest routes the Windows backend through moreSwift/swift-winui products. This is useful existing Windows infrastructure, not a ready-made “real SwiftUI on Mac plus equivalent Windows implementation” SDK. [S3, S4]

Apple's SwiftUI is the Mac rendering foundation. WinUI 3 is the native Windows control foundation. Treat source-level similarity, behavioural equivalence, native appearance, and performance as separately testable properties. [S5, S6]

OpenSwiftUI is a relevant research reference, but its current README lists Windows as unsupported and warns about private Apple-framework dependencies. It is not the initial shipping dependency for this design. [S7]

These observations do not establish production readiness of the selected dependency graph. The first milestone must compile, package, and exercise exact pinned revisions on both target operating systems.

## 3. Architecture decisions

**AD1 — Unmodified toolchains.** Use released Swift toolchains, Swift Package Manager, and supported platform SDKs. Pin a tested compatibility matrix rather than requiring the newest version immediately.

**AD2 — Two compile-time UI implementations.** Implement the portable public surface against SwiftUI on macOS and SwiftCrossUI/WinUI on Windows. There is no JavaScript engine or browser-view requirement for ordinary SDK controls, and no generic JSON UI interpreter in the default path.

**AD3 — App-level state is portable; native objects are not.** Shared domain logic cannot depend on SwiftUI, AppKit, WinUI, React, or Tauri. Platform-owned UI state, focus, window handles, and COM objects remain behind the relevant backend.

**AD4 — Existing engines survive.** Keep working Rust/C/C++ services. Add a versioned service boundary and replace the shell incrementally. Do not rewrite an engine simply to make the repository appear all-Swift.

**AD5 — Portability is a tested contract.** The public SDK specifies supported APIs and behaviours. Broader SwiftUI source compatibility is earned by adding fixtures, not by making unsupported methods silent no-ops.

**AD6 — Upstream-first reuse.** Keep framework-independent WinUI/SwiftCrossUI fixes upstreamable. Own the portable facade, Mac SwiftUI implementation, cross-platform shell services, conformance suite, and migration tooling. Use a narrow pinned fork only when necessary, tracking its divergence.

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
    SwiftRightCore/          # values, command contracts, capabilities
    SwiftRightUI/            # portable UI API and platform selection
    SwiftRightMac/           # actual SwiftUI/AppKit implementation
    SwiftRightWindows/       # SwiftCrossUI/WinUI integration
    SwiftRightServices/      # platform-independent service contracts
    SwiftRightServicesMac/   # native Mac implementations
    SwiftRightServicesWin/   # native Windows implementations
    SwiftRightEngineBridge/  # optional IPC/C-ABI integration contracts
    SwiftRightTesting/       # conformance fixtures and event traces
  tools/
    swiftright/               # doctor/build/run/package/test CLI
    compatibility-check/     # portable API diagnostics
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

This is a proposed modular structure, not a claim that these packages exist. Keep executable app entry points platform-specific while sharing domain and screen modules.

## 5. Shared UI without sacrificing real SwiftUI

Use an intentionally scoped facade. On macOS, supported facade types and modifiers become SwiftUI types/adapters; on Windows, they become equivalent supported declarations/adapters over SwiftCrossUI and WinUI. Native extension views can be embedded through explicit platform entry points.

A conditional import alone does not solve compatibility. The implementation must reconcile protocol conformance, result-builder output, modifiers, property wrappers, generic view types, environment values, and observation lifetimes. That reconciliation is a central workstream.

Prefer compile-time aliases where semantics genuinely match and thin wrappers where they do not. Do not depend on underscored Swift re-export mechanisms or private SwiftUI APIs as the public contract. Avoid blanket type erasure that hides identity or prevents efficient updates. Prove this facade with a small vertical slice before multiplying its surface area.

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

Source support and runtime capability differ. Static unsupported APIs should fail clearly at compile time or through a mandatory compatibility lint. Runtime capabilities such as notification permission need typed availability/denial results and a fallback path.

## 6. State, identity, layout, and events

**Domain state.** Model feature state as ordinary Swift values and explicit commands/effects. Use actors where concurrency requires isolation. Shared services publish versioned state snapshots or bounded event streams. Do not adopt Apple-only observation frameworks as an implicit Windows dependency.

**View-local state.** The facade's state and binding adapters preserve lifecycle on each backend. Shared feature state does not imply that the two platforms share one physical observation engine. Bindings must have tested ownership, writeback, reentrancy, and destruction semantics.

**Identity.** Define stable identity for repeated elements. Add tests where rows are inserted, deleted, filtered, and reordered while selection or text editing is active. A visual list that loses the caret or binds an edit to the wrong row is a failed implementation even when the screenshot looks correct.

**Layout.** Use documented portable sizing/alignment rules while allowing native font/control metrics to differ. Do not require pixel-identical Mac/Windows screenshots. Detect clipping, inaccessible hit targets, scrolling failures, and unreasonable layout costs.

**Events and tasks.** Specify event ordering, cancellation, event coalescing, and subscription teardown. A closed window must not retain its view graph through an unbounded event stream or engine callback.

**Threading.** Shared actors exchange values, not native UI handles. WinUI objects must stay on their owning UI dispatcher; Mac UI work stays on the platform UI thread. The bootstrap spike must establish the relationship between Swift concurrency execution and the WinUI dispatcher rather than assume that annotating a type `@MainActor` completes integration. Do not paper over thread-affinity issues with broad unchecked Sendable conformance.

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
| UpdateService | Signed update metadata, verified payloads, staged install, rollback |
| EngineService | Lifecycle, version negotiation, typed requests/events, cancellation |

Platform-specific code belongs behind these boundaries rather than scattered through every screen. Do not expose a generic unrestricted shell-execution primitive as a convenience replacement for explicit services.

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

Proposed developer interface—not installed commands:

```text
swiftright doctor
swiftright new DesktopUtility
swiftright run --platform macos
swiftright build --platform windows
swiftright test --suite conformance
swiftright package --platform macos
swiftright package --platform windows
swiftright compatibility check
```

Use Swift Package Manager for shared code. Keep Xcode integration for real SwiftUI development and debugging on Mac. Provide SourceKit-LSP/editor integration on Windows. Swift Bundler is a candidate reusable packaging/developer-tool component, not assumed to cover every signing, update, or installer requirement. [S2, S8]

Resolve and pin the complete build tuple: Swift toolchain, Mac SDK/Xcode or Windows SDK/Windows App SDK, WinUI projection, SwiftCrossUI revision, SwiftRight version, and any engine ABI/protocol version. The current upstream package ranges are evidence of dependencies, not the project's future compatibility promise.

Use platform-native CI runners for initial builds. Do not make cross-compiling and signing everything from a single host a prerequisite. Include clean end-user environments without a developer toolchain, install/uninstall, upgrade, failed update, resource loading, DLL/runtime discovery, and first-launch permission behavior.

Mac packaging includes the correct app bundle, resources, entitlements, signing, and applicable notarization workflow. Windows packaging includes required runtime deployment, app identity/manifest choices, signing and installer/update behavior. A window that launches only on the development machine is not a completed platform port.

The SDK should ship prebuilt, reproducibly generated interop artifacts when practical. Do not make each application regenerate the entire Windows API projection. Keep generated bindings separate from hand-authored runtime adapters.

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

## 12. Delivery gates and parallel work

**SR0 — Backend viability and pinned tuple.** Build and package the same small feature on both operating systems using exact dependency revisions. Establish SwiftUI rendering on Mac, WinUI rendering on Windows, event dispatch, state updates, editable text, and accessibility discovery. Prove the compile-time facade concept. Record clean-machine setup and identify unsupported dependencies.

**SR1 — Executable compatibility contract.** Implement the initial UI surface with compile fixtures and behavioural tests. Unsupported APIs fail explicitly. Pass list-identity, binding, focus, cancellation, and teardown tests before expanding control count.

**SR2 — Desktop utility.** Ship a complete internal utility with persistence, menus/tray, shortcuts, dialogs, and an installer/package for each OS. Verify platform capabilities and error paths, not only happy paths.

**SR3 — Engine-backed feature migration.** One real feature runs through the native shell against an existing engine. Tests cover engine crash, restart, incompatible protocol, cancellation, stale events, and rollback to the existing application version.

**SR4 — Production performance and reliability.** Meet measured product budgets, pass clean-machine installation/update tests, and document remaining platform differences. A regression in the critical Mac experience blocks release even if Windows works.

**SR5 — Community release.** Support a second independent application, publish compatibility tables, pinning/upgrade guidance, native escape-hatch examples, issue templates with reproductions, and maintainer ownership for each backend.

Parallel workstreams after SR0's interfaces stabilize are: Mac facade, Windows facade/interop, service layer, independent conformance tests, and packaging/CI. Do not allow each stream to invent its own state, event, or error protocol.

Each agent task specifies an API contract, target platform, fixture, expected failures, source ownership, and evidence required to merge. One model may implement while another builds adversarial tests; both must execute through real compilers and platform tests. Agreement between models is not validation.

Keep source changes and test changes reviewable. An implementation agent cannot silently remove a failing conformance test, relax compatibility claims, or replace native controls with a browser surface to finish a task. A maintainer approves contract changes.

## 13. Long-term maintenance and scope expansion

Define platform owners and a release manager. Maintain a stable pinned lane and a candidate-update lane. Add an upstream change only after conformance, packaging, and representative application tests pass. Publish explicit deprecations rather than chasing every new Apple API immediately.

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
