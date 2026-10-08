# SwiftRight: one Swift codebase, real SwiftUI on Mac, SwiftUI-semantics runtime on Windows

Architecture v0.5 — 8 October 2026

Status: proposed architecture; no implementation or measured performance claimed. v0.5 retains real SwiftUI on Mac & an owned SwiftUI-semantics runtime on Windows, with GPUI as first renderer candidate. It specifies ABI ownership, source/package integration & executable qualification gates; review findings are individually dispositioned. Review history & finding dispositions are in [architecture-review.md](architecture-review.md).

## 1. Product definition

Build a maintained desktop application SDK, not a Swift compiler fork, not a transpiler, and not an emulator for macOS binaries.

The target is **one Swift application codebase whose screens are real SwiftUI on macOS and retain their SwiftUI behaviour on Windows through a SwiftRight-owned runtime.** Existing Rust engines remain reusable and, on Windows, may run in-process as separate versioned libraries alongside the renderer. A UI-only change should not rebuild the Rust rendering stack or an unchanged engine.

Hard requirements:

- One UI codebase. No second hand-maintained shell, no transitional third.
- Real SwiftUI and a direct AppKit escape hatch on macOS.
- On Windows: same source, same intended behaviour, accessible through UI Automation, Fluent-themed where cheap. Not native WinUI controls. Custom-drawn rendering is the same class as the current Tauri/WebView2 shell and is accepted.
- Shipped applications never require Claude, GPT, a network connection, or an AI subscription to render UI or call platform services.

Parity contract: SwiftUI behaviour for a published API inventory, proven by conformance traces recorded on macOS and replayed on Windows. A named SwiftUI SDK version is the ceiling that bounds the inventory, not a promise to implement everything in it.

## 2. Verified starting points

Swift ships Windows toolchains for x86_64 and arm64, a Windows Workgroup since January 2026, and Swift Build as the coming cross-platform default build system. The Browser Company continues toolchain, symbol-server, and static-stdlib work on Windows and was hiring for it in May 2026. Apple's cross-platform investment is in language and toolchain; SwiftUI itself remains Apple-only. [S1, S2, S10, S11, S12, S13]

GPUI evidence must distinguish published artifacts from upstream source. Published `gpui 0.2.2` contains no AccessKit dependency or integration. Upstream source inspected at `b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e` includes AccessKit & a Windows adapter; its GPUI manifest still says `0.2.2`, so that version string does not identify equivalent contents. AccessKit integration merged upstream on 27 May 2026. GPUI remains pre-1.0, Apache-2.0, with frequent breaking changes. [S19, S25, S26]

No renderer/accessibility composition is qualified by this plan. SR0-D must identify an exact consumable distribution, its source revision, lockfile, features, licences & artifact hashes, then exercise its Windows UI Automation surface. A dependency declaration, upstream example or Zed release does not qualify SwiftRight's controls. Published `gpui 0.2.2` alone cannot satisfy this prerequisite. Primary D candidate is published `gpui 0.2.2` plus published `accesskit_windows 0.35.1` with its compatible exact-pinned AccessKit dependencies: GPUI exposes HWND through `HasWindowHandle`, while `SubclassingAdapter` can attach SwiftRight's UIA tree. This is a source-supported composition candidate, not integration evidence. D must prove subclass/window-procedure coexistence, pattern support, lifecycle & native arm64 compilation. AccessKit need not ship inside GPUI. [S38] D enumerates every required platform crate, including Windows/AccessKit glue, with publication status. If no compliant distribution exists, record an external dependency blocker & stop that backend; this plan grants no Git/vendoring exception. An alternative can enter D under the same distribution & rights rules.

Prior SwiftUI reimplementations set expectations. Tokamak, a SwiftUI-compatible framework for other renderers, was archived in January 2026 after covering a basic subset. OpenSwiftUI, the most complete independent implementation, still lists its cross-platform attribute graph as incomplete and text unsupported off Darwin, after years of work. Full SwiftUI parity is therefore scoped by inventory and oracle, never promised whole. [S7, S21]

SwiftCrossUI is a Swift SwiftUI-like runtime with a backend protocol and seven backends; its semantics are its own and it disclaims SwiftUI compatibility. Its WinUI backend sits on an archived binding lineage with an open UI Automation crash; v0.3 no longer depends on it. Its runtime core remains a candidate seed for SwiftRight's runtime, compared in SR0 against a fresh implementation. [S3, S4, S14, S15, S16]

Slint is an alternative renderer candidate. Its platform API adapts Slint scenes to operating-system services; it does not establish that SwiftRight's retained tree can be rendered unchanged. Before fallback selection, prove dynamic tree updates, runtime-owned layout, text measurement, IME & accessibility through SwiftRight's ABI, plus distribution rights for an SDK. No Slint version or drop-in compatibility is assumed. [S22, S23, S27]

Swift–Rust interop has no official bridge. C ABI is supported by both languages; `swift-bridge` generates typed bindings over it. Either is work SwiftRight owns and tests. [S24]

An October 2026 spike shipped Swift 6.3 code as a `@c` DLL on Windows x64 and arm64 and established two reusable facts: Foundation ICU alone is ~37 MB, and Swift main-actor work only runs when the main dispatch queue is pumped from the host UI loop. [S18]

## 3. Architecture decisions

**AD1 — Unmodified toolchains.** Released Swift and Rust toolchains, Swift Package Manager, Cargo, supported platform SDKs. Pin a tested compatibility matrix.

**AD2 — One codebase, two implementations of SwiftUI's programming model.** On macOS, SwiftRight types are SwiftUI's types. On Windows, SwiftRight owns identity, state lifetime, dependency tracking, bindings, environment, layout proposals, transactions & lifecycle, rendering through a versioned C ABI. GPUI is first candidate; Slint is an alternative only after passing that ABI's conformance slice. Backend interchangeability is a qualification result, not an assumption. Application source & public semantics remain fixed during comparison. A second-language shell is never the fallback.

**AD3 — App-level state is portable; native objects are not.** Shared domain logic cannot depend on SwiftUI, AppKit, GPUI, React or Tauri. Swift runtime owns screen identity, edit state & focus intent; backend owns OS focus integration, window handles & renderer resources.

**AD4 — Existing engines survive.** Keep working Rust/C/C++ services. Add a versioned service boundary and replace the shell incrementally. On Windows the engine may load in-process as a separate versioned DLL behind its C ABI; the qualified renderer binary remains unchanged.

**AD5 — Parity is a tested contract with macOS as oracle.** Every API in the inventory has a compile fixture, a behavioural fixture recorded on macOS SwiftUI, and a Windows replay. Unsupported APIs fail at Windows compile time; nothing is a silent no-op.

**AD6 — Own UI semantics, reuse shared capabilities.** SwiftRight owns Windows runtime semantics, bridge, control behaviour, accessibility mapping, Swift service adapters & conformance. Existing RightKit owners supply shared persistence, credentials, process/transport & release capabilities; §7 records adapter gaps separately from capability availability. Qualified renderer artifacts are pinned & isolated behind the bridge. Public API never leaks GPUI or Rust types.

**AD7 — Automation does labour, not judgment.** Agents propose trace updates, renderer bumps & rebuilt artifacts in a candidate lane; they cannot replace accepted traces to make a failing implementation pass. Maintainers decide undocumented semantics & contract changes. Qualification runs on provisioned native hosts under §9; shipped apps require no AI service.

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
                                           paint, text measurement, input, AccessKit
                                           alternative backend only after qualification
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
    SwiftRightUI/          # one module/target, platform-conditional SwiftUI aliases or Windows runtime
    SwiftRightServices/    # service contracts; Mac and Windows targets
    SwiftRightTesting/     # conformance fixtures, trace recorder (Mac), trace replayer (Windows)
  render/
    swiftright-render/     # Rust crate: backend protocol server, GPUI backend, AccessKit mapping
    swiftright-abi/        # C header + generated Swift/Rust bindings, versioned
  services/
    swiftright-services/   # Rust C ABI adapter to shared RightKit capabilities, both OSes
  prebuilt/                # manifests/digests only; native payloads staged outside Git
  scripts/                 # thin RightKit calls, trace candidates, local qualification
  examples/
    ControlsGallery/
    DesktopUtility/
    EngineClient/
  conformance/
  benchmarks/
  docs/
```

Three shipping Swift packages, one testing package & three Rust crates in v1. Split further only when a second consumer needs it.

## 5. SwiftUI on Mac, SwiftUI semantics on Windows

**macOS.** `SwiftRightUI.View`, `State`, `Binding`, `Environment`, and inventory modifiers are SwiftUI's own types. A thin adapter is allowed where it is itself a SwiftUI view and preserves composition and identity. Xcode previews, third-party SwiftUI packages, and the AppKit escape hatch stay intact. Consequence: every SwiftUI API compiles on Mac; only Windows compilation and conformance replay prove inventory membership.

**Source/module contract.** Shared screen files use one conditional import block: `SwiftUI` plus `SwiftRightUI` on macOS, `SwiftRightUI` on Windows; screen declarations stay identical. Import `Foundation` & `Observation` explicitly where used on both platforms; do not depend on SwiftUI transitive exports. Their actual runtime dependency bytes remain in packaging budgets. `SwiftRightUI` has one target name with platform-conditional implementation, not two colliding modules. Mac previews & third-party SwiftUI-only views remain in Mac-only extensions unless separately covered by Windows inventory. No underscored module re-export is required. SR0-C compiles the same screen on both targets, including result builders, property wrappers, generic modifiers & the pinned SDK's `View` actor-isolation contract & at least one SDK-owned symbol, before runtime scoring. Resolve any same-named alias ambiguity in this probe; no platform-specific screen fork is allowed. C may use declaration-only Windows stubs to check type shape; S must replace them with each real runtime & execute identical source.

**Application entry.** One shared root-screen factory & application model are installed by SDK-owned conditional bootstrap. Mac uses a minimal SwiftUI `App`/single `Window` scene; Windows uses a synchronous Swift entry (not async `main`) on the process's initial thread. It initializes the bridge & invokes Rust's blocking loop on that thread; a C loop-ready callback installs the same root before input delivery. B asserts main-actor isolation at every Swift callback boundary & proves initial-thread identity under the pinned toolchain. Applications supply one root plus configuration, not two shells. C freezes the exact consumer entry source, close/quit policy & root lifetime; B/P prove startup, root installation, last-window shutdown & offline relaunch. Arbitrary `App`/`Scene` composition is outside initial inventory. [S33]

**Windows.** The SwiftRight runtime implements SwiftUI's programming model, not its syntax alone:

- View identity: structural identity plus scoped explicit `id`; surviving rows preserve lifetime across unrelated inserts/deletes & reorder. Removal, filtering out, reinsertion or ID change follows the pinned Mac fixture's teardown/reset behavior. [S32]
- State lifetime: `@State` tied to identity; `@Binding` write-back and reentrancy; `@Environment` propagation and overrides; stdlib `Observation` dependency tracking.
- Layout: size proposals, measurement, alignment guides, placement, `Layout` protocol, `GeometryReader`, safe-area and scroll geometry.
- Transactions and animation: implicit and explicit animation, interruption, completion, reduced motion.
- Lifecycle: `onAppear`/`onDisappear`, `task` cancellation, preference keys, focus state.
- Text input: editing, selection, undo, IME composition, keyboard-only use.

The Swift runtime owns final layout & produces a retained tree with resolved geometry. Rust supplies text/control measurements, paints committed geometry & reports input, focus & accessibility events. It cannot independently relayout Swift-owned children. Every inventory control needs behaviour tests & an AccessKit mapping; Fluent styling is allowed only within its documented presentation differences.

**Runtime seed.** SR0 compares two seeds on the decision slice: a fork of SwiftCrossUI's runtime core with a GPUI backend, and a fresh runtime written to SwiftUI semantics from the start. Choose by replay results and by how much SwiftCrossUI semantics must be rewritten.

**Rejected.** Wrapper-only on Mac (loses real SwiftUI at the type level). SwiftCrossUI as compatibility foundation (its semantics are its own; its WinUI backend chain is archived and crashes under UI Automation). Any SwiftUI-to-Slint/GPUI/Compose transpiler (no such tool exists; a compiler to maintain against every SwiftUI release; parity is semantics, not syntax). A C# WinUI or other second-language shell (breaks one codebase).

### Initial inventory

Text, buttons, toggles, single- and multi-line editable text, images, stacks, spacing, padding, alignment, scrolling, lists with selection and editing, menus, dialogs, one main window, keyboard actions, focus, basic animation. Each item ships with compile fixture, macOS trace, Windows replay, and accessibility assertions.

SR0's custom `Layout` fixture is a feasibility probe, not a claim of full protocol coverage. SR0 already covers observable row realization/lifecycle required by its list fixtures; exact platform overscan is not an assertion. Expansion milestones: large-data virtualization optimizations, tables, navigation, multiple windows, drag/drop, broader `Layout` support & gestures. Document editors, canvas systems, and media timelines do not shape the first release.

### Compatibility categories

- **Inventory:** same source, same traced behaviour on both platforms.
- **Adapted:** same intent with a documented presentation difference (menu placement, control metrics, Fluent theming).
- **Platform extension:** intentionally Mac-only or Windows-only module.
- **Unsupported API:** absent or explicitly unavailable Windows declaration; negative compile fixtures prove diagnostics. Combine-based `ObservableObject`, `StateObject`, `ObservedObject` & `onReceive` are initially outside inventory.
- **Unsupported value/composition:** a type-checkable API can receive unsupported runtime values. Publish those restrictions separately with deterministic diagnostics; never claim these fail at compile time or silently ignore them. Inventory fixtures cover every promised composition.

## 6. State, identity, layout, events, threading

**Domain state.** Ordinary Swift values, explicit commands and effects, actors where isolation is required, stdlib `Observation` on both platforms, macOS 14 floor.

**Identity and lists.** Tests distinguish a surviving active row amid unrelated edits/reorders from removal, filtering out, reinsertion & explicit-ID changes of that row. Surviving-row caret/composition must remain attached to its identity; removed-row state, focus & composition must follow recorded Mac teardown/reset outcomes. No edit may target a different or resurrected row through a stale handle.

**Layout authority.** Swift owns proposals, alignment, placement, scroll geometry & final hit-test bounds. Rust owns font shaping, glyph rasterization & intrinsic native metrics. Measurement is a synchronous, read-only C ABI query on Windows' UI thread, before frame commit; it returns size, baselines & an explicitly retained shaped-run handle. It cannot call Swift, pump tasks, change tree state or wait for work scheduled on that same thread. Cache keys include text, font/version, proposed width, locale, direction & DPI. Measure requests are batched where possible; all crossings count toward §11 budgets.

Swift commits geometry, text-run handles, focus target & accessibility-node changes as one versioned transaction. Rust paints & hit-tests that snapshot without changing placement. Events identify window generation, node identity & snapshot version; stale events cannot edit a reused row or closed window. Rust reports OS text/IME events; Swift owns editable buffer, selection, undo & composition state, returning current caret geometry to Rust's OS adapter. A width-dependent text fixture verifies that measured, painted, hit-tested & accessible bounds agree before ABI v0 is frozen.

**Native text input.** Initial GPUI candidate uses its observed IMM32 message path (`WM_IME_COMPOSITION`), not an assumed TSF text store. `swiftright-render` owns adaptation from that handler to a versioned C function table for Swift-owned text (plain C entry points & opaque context, no captured closures). D proves selected distribution's hand-authored text node can receive committed/marked text, selection/range queries & candidate positioning; C freezes its exact IMM32 contract. Calls run on the UI/main-actor thread with document access guards, UTF-16 ranges, bounded buffers & typed failure. No task pumping, frame commit or view reconciliation occurs inside callbacks; mutations reconcile after native callback unwinds. B tests nested query/edit access, cancelled composition, stale focus/window handles & teardown. During Swift measurement/commit no callback into Swift is permitted. TSF lock upgrades/reconversion are not claimed by this path; adding a TSF store requires named ownership, disabling competing IMM handling & fresh D/B qualification, including TSF lock rules [S28]. [S35]

**Accessibility & paint vocabulary.** Swift owns semantic nodes/actions; one Rust AccessKit adapter per HWND publishes SwiftRight's tree & routes actions to Swift identities. Action handlers only enqueue generation/node/snapshot/action records & wake the UI loop; they never invoke Swift directly from an AccessKit callback thread. B fires off-thread actions during window closure & verifies stale-action rejection. [S36] D must prove external tree publication/OS-hook ownership with a hand-authored SwiftRight tree, not merely discover GPUI controls. B proves the same route through ABI. C freezes a retained primitive vocabulary (text runs, images, paths, clips, transforms & geometry), plus semantic nodes separately. Swift controls produce those primitives using queried theme metrics; Rust does not substitute an independently laid-out control tree. Probe every primitive required by the slice before freezing ABI.

**Events and tasks.** Specify ordering, cancellation delivery, coalescing & teardown. Swift cancellation is cooperative, not a ban on every subsequent mutation. Shared application/fixture effects check cancellation & owner generation immediately before committing results, with generation check plus commit serialized on owning actor. Runtime delivers cancellation & rejects destroyed bridge handles; guarded stale results must not mutate replacement state. Legitimate cleanup remains observable & permitted. [S31] A closed window must not retain its element tree through an unbounded stream or engine callback.

**Threading and the bridge.** Rust owns Windows' UI event loop & rendering resources. Swift's main actor runs on that UI thread through a tested dispatch integration; it is never pumped recursively during measurement or commit. Verify wake-up, cancellation, idle behaviour & queue fairness under load, including while windows are closing. Bridge rules: opaque generation-tagged handles, explicit retain/free & buffer lifetimes, batched frame commits, bounded queues with declared overflow errors, typed failures & no Swift closures across ABI. Rust panics never unwind into Swift; distinguish recoverable errors from process termination, including aborting builds. SR0 injects stale handles, queue overflow & teardown races. UI-only changes reuse unchanged Rust artifacts; linking is measured separately from rebuilding them.

**Loop borrow boundary & frame clock.** Drain Swift jobs only at an integration point where GPUI application/window borrows are released. Swift-callable measurement uses independently retained immutable resources; commit records enter a bounded Rust-owned buffer & GPUI consumes them after drain returns. No C entry borrows an already-borrowed `AppCell` or holds Rust locks across a Swift callback. B exercises measure/commit during permitted Swift drains without re-borrow panic. Inside IME callbacks it exercises only permitted synchronous text queries/edits, rejects or defers attempted frame commits, then verifies reconciliation & buffered commit after callback unwind. Rust supplies coalesced, on-demand display ticks with monotonic target-frame timestamps through the UI queue; Swift advances animation & commits before presentation. Stop ticks when idle/closed, bound tick-to-commit cost & include all queue/frame waits in §11. [S37]

**Wake/drain candidate.** GPUI 0.2.2's public foreground executor posts runnables to its message-only platform window; its normal dispatcher & size/menu timer provide candidate borrow-free runnable sites. D verifies that route, Swift-queue wake/reschedule delivery, modal timer cadence & live-resize latency before adopting it; source inspection alone does not prove §11 budgets. B completes shutdown-critical Swift cleanup before closing the executor/loop, since late GPUI dispatches can be dropped; reject new work after shutdown begins & fault-test late dispatch. [S40]

**Modal-loop policy.** C freezes a non-reentrant drain guard across every host callback, not just measurement/commit. Window-targeted wake messages may drain during external modal loops (including live resize) only when no Swift drain/job or GPUI borrow is active. Swift-initiated menus/dialogs are requested asynchronously, opened after current drain & borrows unwind, then report results through the bounded UI queue. B resizes width-dependent text during async updates & opens one modal UI request from Swift; assert no nested drain/borrow panic, responsive layout, teardown & unchanged queue-latency budgets. Thread-only wake messages are insufficient for modal-loop progress. [S39]

**Binary compatibility.** Renderer & services expose a fixed, minimal C bootstrap query returning ABI/schema identity, architecture, pointer width & required function-table sizes into caller-sized buffers. Exact compatibility is initially required, including Swift callback tables. Validate before exchanging runtime-owned allocations, installing callbacks or starting UI/services; mismatch produces deterministic startup diagnostics. D proves query/link mechanics with disposable sentinel binaries; B/P deliberately mix incompatible headers, libraries & callback tables & require rejection before callbacks. Payload checksums prove identity, not interoperability.

**Dispatch mechanism.** D first checks whether the pinned released toolchain offers a documented executor integration compatible with the host loop; prefer it if B proves identical requirements. No such hook is presumed available. Otherwise initial B probe isolates the Windows dispatch-queue drain used in [S18], `_dispatch_main_queue_callback_4CF`, behind a version-pinned shim. This is a private symbol compatibility risk, not a supported Swift API claim. D checks export/link availability; B must establish nonrecursive wake/drain integration with GPUI, including idle & starvation budgets. Released toolchains stay unmodified. Missing symbol or failed integration blocks B; a replacement must reopen its evidence. Foundation `RunLoop`/`Timer` & Combine-driven scheduling are outside the initial Windows contract; fixture/application async work uses qualified Swift concurrency & injected clocks.

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

### Workspace capability integration

SwiftRight is the explicitly requested Swift desktop SDK; its UI runtime intentionally differs from the existing Rust/React app template. Shared capabilities & release ownership remain with RightKit; this does not alter workspace defaults.

These are intended integration owners, not claims of working Swift adapters. Before implementing each interface, confirm exact published version, supported features & native-host evidence using `rightkit owns <capability>` plus workspace source. Registry availability, source implementation & SwiftRight integration are separate facts. Consume published exact pins; report missing adapters or capability gaps under existing owners instead of copying implementations.

| SwiftRight need | Existing owner to evaluate | SwiftRight work |
|---|---|---|
| Settings & persistence | `rightkit-settings`, `rightkit-db` | Swift value mapping, app namespaces & migration tests |
| SecureStore | `rightkit-secrets`; `RightKitSwift` on Apple | Availability/error mapping; validate Windows & Apple credential access |
| EngineService | `rightkit-process`, `rightkit-framed-sidecar`, `rightkit-service` | Swift client, cancellation & engine protocol adapter |
| Window/tray/launch | `rightkit-shell` | Separate Tauri-specific portions from reusable OS functions; GPUI keeps window ownership |
| Global hotkeys | `rightkit-hotkeys` | Publication & native integration remain prerequisites; declaration alone is insufficient |
| Diagnostics & native QA | `rightkit-logs`, `rightkit-crash`, `rightkit-qa`, `rightkit-automation` | Swift runtime events & real AX/UIA assertions; qualify required features on each OS |
| Packaging, signing & updates | `@rightkit/release`, `@rightkit/updates` | Product configuration & Swift/prebuilt inputs; route missing package-format support to shared tooling |

Window-specific adapters may use Swift over Win32/COM or Rust where GPUI owns resources. Clipboard, dialogs & notifications require an ownership lookup before selecting direct OS adapters. No generic shell-execution primitive. Update delivery follows existing RightKit policy & product configuration; this SDK does not create another updater.

Mac-specific features stay first-class through the Mac extension module. Core ML, Metal, and other Apple-specific components are not made portable by the UI layer; applications choose a Windows implementation behind the service contract.

Mac consumes Apple-qualified `RightKitSwift` where available; other Rust-owned capabilities use the thin `swiftright-services` C ABI library on both OSes. It contains adapters, not duplicated services. Qualify native service artifacts independently of Windows renderer; Mac must not link GPUI merely to access persistence. D records each missing Swift/C ABI adapter against its RightKit owner, status & evidence needed to unblock its consuming stage.

## 8. Retaining Rust engines

Default migration path: Swift client adapters over RightKit-owned process & transport capabilities, communicating with existing Rust engines through inherited pipes or user-restricted sockets/named pipes. Preserve handshake, version range, correlation, timeouts, queue bounds, typed errors, shutdown & reconnect; implement only application protocol mapping in SwiftRight. Required shared-package feature gaps stay with their owner.

On Windows, the engine may instead load as its own versioned DLL in the same process, exposing the same protocol over C ABI. Rust types, allocators & unwinding never cross DLL boundaries; each library frees its own allocations. Do not statically combine engine & renderer in v1. Choose per app by measurement; keep the out-of-process path as rollback.

High-rate data (audio, frames, inference) stays inside the engine. Exchange commands, transcripts, status, and bounded progress with the UI. Never route raw frames through JSON.

In-process C ABI between Swift and Rust follows the bridge rules in §6: ownership, opaque handles, error values, thread rules, buffer lifetimes, panic containment.

## 9. Tooling and distribution

No bespoke CLI in v1. Swift Package Manager builds Swift; managed `rightkit cargo` builds Rust on each native host. Xcode serves Mac development & SourceKit-LSP Windows. Repository scripts are thin qualification/RightKit callers. Swift Bundler may supply unsigned app preparation where compatible; it does not own signing or installer machinery.

**Prebuilt renderer.** SR0-D selects an exact published dependency set that lets SwiftRight publish its own UIA tree; a newer upstream Git checkout is not a substitute for an available distribution. Record package checksums, source revisions, licences, lockfile, feature set, native target & build recipe. Build `swiftright-render` on native Windows x64 & arm64 hosts & `swiftright-services` on each supported Mac/Windows architecture through managed RightKit, with artifact digests bound to those inputs. A second build checks reproducibility of unsigned payloads; signing evidence binds final artifacts separately. Swift consumers reuse these artifacts; a screen-only edit must invoke no Rust compilation. `prebuilt/` stores manifests/digests only. Native build/seal outputs live outside Git; requested SDK publication supplies checksum-pinned payloads through configured RightKit/R2 delivery. D/B/P can qualify local staged payloads without publication; no upload follows implicitly from a gate.

**SwiftPM consumption.** Initial Windows packaging uses a C `systemLibrary` target/module map for headers & import library, plus a separately installed, checksum-pinned SDK payload containing DLLs. A thin consumer build invocation supplies SDK search paths; published dependency manifests must not require `unsafeFlags`. Do not assume Windows `.binaryTarget` support. D proves a separate downstream SwiftPM application can resolve, link & load a disposable C ABI sentinel payload without Rust sources or a Rust compiler; B repeats with real renderer/services artifacts before ABI freeze; P proves app-local DLL staging, transitive dependencies & clean-machine loading. Mac service artifacts use the same C boundary with native packaging. Mechanism remains unqualified until those probes pass. [S29]

**Pinned tuple.** Swift/Rust toolchains, macOS runtime build, Mac SDK/Xcode, Windows runtime/SDK, architecture, GPU/driver, renderer distribution & source revision, AccessKit revision, features, bridge ABI, dispatch shim/symbol contract, SwiftRight & engine protocol. Benchmark metadata also pins fonts, locale, DPI, power mode & display refresh. An SDK version alone does not identify SwiftUI runtime behaviour. C enumerates supported macOS runtime builds, at minimum the macOS 14 floor & newest supported release; every advertised runtime/architecture pair gets its own accepted trace lane. Initial Mac architecture is arm64; Intel/universal distribution is unclaimed until native x86_64 build/test capacity & full qualification exist. D records actual Mac OS builds/architectures & stable signed recorder/replay-driver identities with required AX/input permission grants; missing access or runtime blocks that lane/O. Missing macOS 14 floor capacity blocks O/SR0 while that floor remains required; no automatic floor increase or dropped support claim is permitted. Missing oracle-of-record capacity also blocks O. Use provisioned signing through RightKit, not ad hoc signer setup. Differences require explicit per-version adaptations or removal of that support claim; one passing runtime cannot qualify others. Windows oracle of record is the newest supported Mac arm64 lane frozen in C; differences on other supported Mac lanes are explicit version adaptations. Changing oracle of record reopens comparison for both seeds.

**Packaging.** RightKit `right-release` owns native build/sign/package/seal mechanics. Apple & Azure signing are provisioned; no enrollment or signer setup gate is needed. Mac inputs are app bundle, resources & entitlements. Windows target is MSIX with package identity & an explicit Swift runtime dependency inventory from selected toolchain. Prove clean-machine loading; do not assume future static-stdlib support. A missing Swift/MSIX adapter is a shared-tooling gap, not permission to implement signing/installer scripts here. Clean-machine install, uninstall, upgrade, interrupted/failed update & first-launch permissions are required on both OSes. D performs an adapter preflight for Swift inputs, Mac app bundles, MSIX & its update path against current `right-release`; missing support is an explicit prerequisite owned by `@rightkit/release`, not presumed available. P also fixes package trust/virtualization settings & verifies original data paths, migration/rollback & engine endpoints from the installed app; new writes must remain readable by the rollback shell & uninstall must preserve declared user data. MSIX virtualization depends on manifest/OS configuration. [S30]

**Execution hosts.** This private `bogusyogi` repository requires local native Mac, Windows x64 & Windows arm64 hosts; availability of all three is not asserted. No GitHub Actions workflows or billed runners. SR0-D records actual availability; a missing native architecture blocks its qualification instead of being replaced by cross-compilation. Builds, tests & signing run on their target host. Build/seal remains separate from publication; private product uploads use configured RightKit/R2 delivery only when requested. Workspace runbooks: `docs/rules/rightkit.md`, `docs/rules/github-access.md`, `docs/rules/release-signing.md` & `docs/RIGHTKIT-SHARED-PLATFORM.md` in `bogusyogi/claude`.

## 10. First consumers and migration

Begin with a real desktop utility/settings screen: persistent state, editable text, a list, tray entry, shortcut, dialog, releasable package.

For HeardRight-like functionality: settings or command history against the existing engine first, then resident/tray behaviour, then overlay/audio workflows.

Keep the current app functional while adding the new shell behind a development/release option. Preserve file formats and IPC semantics. Migrate one complete feature at a time. React/TypeScript screens are rewritten once into SwiftUI; thereafter one source serves both platforms.

RustRight's CLI must not depend on this SDK; the SDK must not require RustRight to build.

## 11. Conformance and performance

Three test layers: inventory contract tests, platform interaction tests, complete application tests.

### Executable oracle contract

Fixtures replay input stimuli, never recorded output state. Each inventory entry identifies exact APIs/overloads, supported compositions, initial state, stable node IDs, stimulus sequence, observable assertions & unsupported compile cases. Fixture metadata binds source hash, trace schema, pinned platform tuple & adaptation rules. Recorder combines in-process public instrumentation (app state, bindings, lifecycle/effects) with out-of-process native AX/UIA observations & input. C defines canonical roles/actions, UTF-16/text-range mapping & observation availability per fixture. Mac internals such as marked-text state need a public native observation route or a bounded input/output assertion; no private SwiftUI introspection is assumed. Missing observability blocks that assertion before seed comparison.

- **Stimuli & scheduling:** timestamped logical actions with frozen per-platform native inputs: keyboard, pointer, focus, text composition & application effect completions. C maps standard commands (for example Copy: Command-C on Mac, Ctrl-C on Windows) & modifier semantics explicitly as adaptations. Raw-key API fixtures separately test physical keys/modifiers. “Identical stimuli” means identical logical intent plus its declared native mapping, never bypassing controls with direct state writes. [S34] Inject fixture clocks & fake engine responses into app-owned work; control when async results become available. Do not assume control over SwiftUI's private scheduler. Specify required event partial orders, observable settlement conditions & timeouts instead of matching incidental callback timing.
- **Observations:** state, identity, selection, caret/composition, focus, layout & accessibility; instrument public lifecycle callbacks, effect start/cancel/complete & committed side effects. Deliver late completions after cancellation & window closure; shared guarded effects must reject stale-owner results & destroyed-view delivery, while fixture-declared cleanup remains allowed. Record animation interruption/completion & reduced-motion outcomes, not just endpoints.
- **Normalization:** compare exact semantic values & stable identity. Canonical accessibility nodes preserve role, label, value, supported actions, focus & meaningful parent/child order. Strip only named platform-generated containers/IDs. Keep native trees for debugging. Every adapted entry names allowed metric/presentation differences & bounds; no blanket timing or geometry tolerance. Layout assertions include containment, clipping, minimum hit targets, caret visibility & agreement between paint, hit-testing & AX/UIA bounds.
- **Repeatability:** run each Mac fixture 20 times on its pinned runtime. All normalized semantic assertions & required orderings must agree before it becomes an oracle. Variance becomes an explicit permitted ordering or fixture defect. Each seed on each Windows architecture also executes 20 independent runs of identical logical stimuli & assertions, all passing. This correctness repeat count is separate from timed workload runs. Inject wrong row identity, a stale task commit & a missing accessibility action to prove comparator rejects each fault.
- **Native interaction:** recorded logical IME actions test runtime state; real OS IMEs, Narrator/NVDA & keyboard navigation separately test platform integration. Neither substitutes for the other. Native checks verify actions affect intended model state, beyond merely exposing controls.
- **Change control:** retain accepted traces, assertions & environment metadata. New OS/toolchain observations create candidate baselines; compare them against accepted expectations before adoption. Automation cannot bless drift by regenerating expected output.

Cover state and binding lifecycle, focus, undo/redo, Unicode and IME, keyboard-only use, accessibility roles/labels/actions through UI Automation on Windows and the accessibility API on macOS, right-to-left, high contrast, reduced motion, DPI scaling, multi-monitor, window reopen, subscription teardown.

**Windows accessibility gate.** C specifies required UIA patterns per inventory control, including editable-text reading by character/word, selection, caret & text-range bounds; role/value alone is insufficient. D proves pinned AccessKit supports those patterns on its hand-authored nodes, then S verifies live edits & range actions via Narrator/NVDA. A UI Automation walk of every shipped window completes and exposes every control; Narrator and NVDA activate inventory controls. Screen-reader failure is a release blocker.

### Decision budgets

These are initial engineering acceptance limits, not measured results or upstream guarantees. Freeze them with SR0-C fixtures before either seed is scored. Mac & Windows have separate records; Windows x64 success cannot qualify arm64. Any later limit change requires a documented contract revision & rerun of both candidates on the same workload.

SR0 workload: 200 stable-ID editable rows, 20 asynchronous row updates/inserts per second, one reorder per second, continuous scrolling & editing, with fixed-size data maintained by removing unrelated rows. Include width-dependent text layout, interrupted animation, cancellation & window teardown. Pin logical window size, fonts, DPI, input script & 60 Hz display. Use release builds without debugger; after 10 seconds of warm-up, collect three 60-second runs. Every run must pass; archive raw samples & report p50/p95/p99. C specifies monotonic input timestamps & actual presented-frame endpoints per OS (validated compositor instrumentation or synchronized optical capture); enqueue/draw callbacks alone cannot establish visible response. Measure instrumentation overhead & bind clock correlation/calibration to run metadata. IME & screen-reader correctness scenarios run separately with native tools.

| Measurement | SR0 pass condition |
|---|---|
| Identity, text edits, cancellation & accessibility actions | Zero wrong-node edits, lost valid commits, stale-owner result commits or missing required actions |
| Windows bridge handling per input event | p95 ≤ 1 ms; p99 ≤ 2 ms |
| Windows aggregate bridge time per committed frame | p95 ≤ 2 ms; p99 ≤ 4 ms, including synchronous measurement, encoding, copying & commit; do not double-count nested calls |
| End-to-end input to visible response, each OS | p95 ≤ 50 ms; p99 ≤ 100 ms; include all queueing & frame waits |
| Frame presentation interval during continuous animation/scroll | p95 ≤ 16.7 ms; p99 ≤ 33.4 ms on fixed 60 Hz display |
| Swift main-actor enqueue to execution on Windows | p99 ≤ 16.7 ms under slice load; no deadlock or starvation |
| UI-only incremental build | Zero Rust compiler invocations; renderer & unchanged engine artifact hashes stay identical |

For SR2/SR4, measure same feature & engine in existing React/Tauri shell on each reference machine before migration. Freeze baseline package size, process-tree memory, CPU wakeups & startup-to-interactive. Initial non-regression limits: startup p95, steady-state process-tree memory, idle wakeups & shipped bytes each ≤ 110% of that OS baseline; screen-only incremental build median ≤ baseline, using 10 edits per shell in the same release incremental rebuild-and-relaunch mode, measured from saved source edit to first visible updated frame; record build/link/launch subintervals separately. Hot reload is excluded from this comparison & may be reported separately. Startup uses 30 fresh process launches with cache state recorded; memory uses three 60-second steady-state samples; idle wakeups use three 60-second idle samples. Missing comparable baseline blocks that performance claim. Shipped bytes include all app-distributed Swift/ICU/renderer/service dependencies for both shells; report installed shared prerequisites separately. Measured overhead may fail this gate; no automatic runtime exclusion or budget increase is allowed. Both platforms must still pass absolute interaction limits above; no predicted Mac win counts as evidence.

## 12. Delivery gates

**SR0 — Decision slice.** One feature through Apple SwiftUI & Windows: an editable, reorderable list with an async insert above active edit; width-dependent custom `Layout`; interrupted animation; async cancellation; keyboard/IME editing; accessibility inspection & activation. Restrict both seeds to identical slice inventory. Each stage below has a pass/fail result; later stages cannot treat an earlier missing prerequisite as passed.

| Stage | Deliverable & required result | Depends on |
|---|---|---|
| SR0-D: dependencies & hosts | Select exact published renderer/AccessKit composition capable of SwiftRight-owned UIA tree publication; record native x64/arm64/Mac hosts, RightKit owner/adapter map, toolchains & package checksums. Prove SwiftRight-owned external semantic tree publication/action routing & chosen IMM32 text-node path on both Windows architectures; validate downstream SwiftPM prebuilt loading, dispatch symbol, foreground-executor wake/drain route including modal cadence & named shared packaging/adapter gaps. Missing distribution/host or failed native gate blocks GPUI-dependent work. | None |
| SR0-C: slice contract | Freeze exact slice APIs, inputs, expected effects, normalized assertions, negative fixtures & §11 budgets. Define public subset of custom `Layout`, row lifecycle assertions, primitive/semantic ABI vocabulary, observation/measurement routes, native shortcut mappings & same-source entry/module compile probes (declaration stubs allowed, behavioral proof deferred to S). | None; may run alongside D |
| SR0-O: oracle & comparator | Run Mac recorder repeatedly; pass repeatability. Build comparator & replay-driver skeleton before seed selection; prove deliberate semantic faults fail. Windows runtime results arrive at S. | C |
| SR0-B: bridge & measurement | Prove runtime-owned layout with a hand-authored tree, width-dependent text, coherent paint/AX bounds, editable-text UIA ranges/caret bounds through committed text-run handles, non-reentrant main-actor pumping, bounded queues, IMM32 text callbacks, off-thread AX actions, borrow-safe dispatch/frame ticks, initial-thread root startup/shutdown, binary compatibility rejection & teardown. Build native x64/arm64 prebuilt artifacts & freeze ABI v0 only after this probe. | D, C |
| SR0-S: seed comparison | SwiftCrossUI-core fork candidate & fresh runtime execute frozen slice through same qualified backend. Both run compiler checks, oracle assertions, native IME/UIA actions & budgets on each target; select only a fully passing seed. Among passing seeds, prefer fewer semantic overrides & lower measured bridge/runtime cost. | O, B |
| SR0-P: packaged qualification | RightKit produces signed Mac app & signed Windows MSIX. Clean machines install, launch offline, upgrade, reject corrupt updates, recover interrupted updates & uninstall. Verify all runtime dependencies, per-arch artifacts & unchanged Rust binaries after a Swift-only edit. | Selected passing S; shared packaging adapters available |
| SR0-A: repeatable automation | Local native qualification jobs replay accepted fixtures, propose trace/pin updates in candidate lane & exercise UIA. Emit structured stage-start/pass/fail output with artifact/fixture identity. SR0 closes only when D through A pass. | P |

One initial attempt & at most one targeted repair per failing stage/candidate. Repeated failure ends that candidate's SR0 attempt; record failing fixture, layer & evidence before changing direction. Shared-stage failure (D/C/O/B/P/A) after its cap stops SR0 until Adrian resumes or changes scope; a dependency availability blocker is reported without consuming speculative repair attempts. Do not reset retry counts by renaming a stage or switching renderer. Missing prerequisites stop dependent work immediately. This gate sequence replaces v0.3's calendar deadline; no delivery ETA is asserted before dependency & host qualification.

### Failure-specific fallback

| Failure owner | Required disposition |
|---|---|
| Distribution, licence, native host or packaging prerequisite | Resolve through existing owner or mark candidate unavailable; no fake qualification, ad hoc signer or billed private CI |
| Oracle repeatability or comparator | Repair fixture/normalization within stage cap; seed selection stays blocked |
| Runtime identity, binding, task lifetime or layout semantics | Repair/reselect seed against unchanged fixtures; if neither passes, stop SDK expansion & retain existing app |
| Bridge latency, queueing, lifetime or dispatch | Isolate cost with same input/tree; repair ABI/batching/threading within cap, then rerun B & downstream stages already started, including S for both seeds if comparison began. Renderer swap alone is not resolution |
| GPUI-specific painting, intrinsic measurement, OS IME or accessibility | Diagnose selected native handler versus SwiftRight adapter first; repair adapter-owned faults under B, or consider Slint only for demonstrated backend defects after equivalent qualification |

IME & accessibility failures require layer diagnosis: wrong composition state or missing semantic action can originate in Swift runtime, not renderer. For any alternative, first settle SDK redistribution rights, then run same dynamic-tree, measurement, focus, IME, accessibility & latency probes on both Windows architectures. No transpiler or second application shell is allowed. A backend qualifies only if application source & public contract stay unchanged; required ABI changes reopen B & all downstream gates. Until Slint passes, it is an unqualified candidate, not an available recovery path.

**SR1 — Inventory contract.** Initial inventory with fixtures, traces, replays. Unsupported APIs fail at Windows compile. List identity, binding, focus, cancellation, teardown pass before adding controls.

**SR2 — Desktop utility.** Complete internal utility with persistence, menus/tray, shortcuts, dialogs, installer per OS. Error paths verified.

**SR3 — Engine-backed feature.** One real feature through the shell against an existing engine, in-process on Windows if measured better. Tests cover crash, restart, incompatible protocol, cancellation, stale events, rollback.

**SR4 — Production performance and reliability.** Budgets met, clean-machine install and update, platform differences documented. A Mac regression blocks release even when Windows passes. Any non-regression failure blocks release; retain existing shell while Adrian decides a documented contract change, further authorized repair or stopping migration. No failed size/performance gate is silently waived.

**SR5 — Community release.** Second independent application, inventory tables, pinning guidance, escape-hatch examples, issue templates, backend ownership.

Parallel workstreams after SR0: Mac adapters, Windows runtime, renderer crate, service adapters, conformance & RightKit packaging integration. One state, event & error protocol across all streams.

Each agent task specifies API contract, platform, fixture, expected failures, ownership, and evidence to merge. One model implements while another builds adversarial tests; both execute through real compilers and platform tests. Agreement between models is not validation. An agent cannot remove a failing conformance test, relax an inventory claim, or substitute a browser surface. A maintainer approves contract changes.

## 13. Long-term maintenance

Platform owners & release manager maintain accepted/candidate lanes. Automation proposes trace updates, renderer pins & prebuilt artifacts, then runs local native qualification. Maintainers own undocumented semantics & acceptance changes. Use provisioned native hosts & signing accounts; record any missing Windows arm64 capacity or shared adapter as an availability gap, not an assumption of new infrastructure spending.

GPUI changes land in candidate lane behind bridge & must prove unchanged application fixtures before promotion. Track provenance & licence for every reused Zed component individually; only `gpui` itself is assumed Apache-2.0. Renderer distribution upgrades rerun native accessibility, text/IME, bridge & packaging qualification.

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

[S19] GPUI upstream source snapshot, including manifest & README; distinct from published 0.2.2: [Zed b47a4ca, GPUI](https://github.com/zed-industries/zed/tree/b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e/crates/gpui), [Windows adapter](https://github.com/zed-industries/zed/blob/b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e/crates/gpui_windows/src/window.rs).

[S20] GPUI site: `https://gpui.rs`

[S21] Tokamak, archived January 2026: `https://github.com/TokamakUI/Tokamak`

[S22] Slint default style change to Fluent: `https://slint.dev/blog/default-native-style-change`

[S23] Slint changelog (1.15–1.17, native handles, accessibility): `https://github.com/slint-ui/slint/blob/master/CHANGELOG.md`

[S24] swift-bridge, Swift–Rust FFI generator: `https://github.com/chinedufn/swift-bridge`

[S25] Published GPUI 0.2.2 [manifest](https://docs.rs/crate/gpui/0.2.2/source/Cargo.toml) & [crate archive](https://crates.io/api/v1/crates/gpui/0.2.2/download). Archive inspection found no AccessKit references in Rust sources, manifests or docs.

[S26] GPUI [AccessKit integration PR #56065](https://github.com/zed-industries/zed/pull/56065), merged 27 May 2026; upstream integration alone does not prove control-level accessibility.

[S27] Slint [platform API](https://docs.slint.dev/latest/docs/rust/slint/platform/): interface between Slint & OS/windowing services, not evidence of SwiftRight backend interchangeability.

[S28] Microsoft [TSF document locks](https://learn.microsoft.com/en-us/windows/win32/tsf/document-locks): synchronous access, reentrant lock upgrades & deferred grants.

[S29] SwiftPM [PackageDescription](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html): system-library targets, linker settings & unsafe-flag dependency constraints; target-host consumer probe remains required.

[S30] Microsoft [packaged desktop runtime behavior](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes): manifest/OS-dependent file & registry virtualization.

[S31] Apple [Task.cancel](https://developer.apple.com/documentation/swift/task/cancel()): cooperative cancellation.

[S32] Apple [Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/): identity & state lifetime.

[S33] Apple [App](https://developer.apple.com/documentation/swiftui/app): application entry & scenes; Windows bootstrap is SwiftRight-owned.

[S34] Apple [keyboardShortcut](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)): command-modifier API; cross-platform command mappings are explicit SwiftRight adaptations.

[S35] GPUI [Windows events at inspected snapshot](https://github.com/zed-industries/zed/blob/b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e/crates/gpui_windows/src/events.rs): observed IMM32 composition & candidate-window path, not proof of a qualified distribution.

[S36] AccessKit Windows [Adapter](https://docs.rs/accesskit_windows/latest/accesskit_windows/struct.Adapter.html): action-handler thread may differ from window thread; selected version must requalify this boundary.

[S37] GPUI [AppCell](https://github.com/zed-industries/zed/blob/b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e/crates/gpui/src/app.rs) wraps application state in `RefCell`; SwiftRight must prove its borrow-safe integration point.

[S38] Published composition evidence: [GPUI 0.2.2 Window/HasWindowHandle](https://docs.rs/gpui/0.2.2/gpui/struct.Window.html), [AccessKit Windows 0.35.1 source](https://docs.rs/crate/accesskit_windows/0.35.1/source/). Archive inspection confirms `SubclassingAdapter`, UIA text-provider implementation & GPUI's IMM32 path; native composition remains untested.

[S39] Microsoft [WM_ENTERSIZEMOVE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-entersizemove) & [PostThreadMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postthreadmessagew): modal-loop behavior; SwiftRight must qualify window-targeted wake/drain integration.

[S40] Published GPUI 0.2.2 [dispatcher](https://docs.rs/crate/gpui/0.2.2/source/src/platform/windows/dispatcher.rs), [platform window](https://docs.rs/crate/gpui/0.2.2/source/src/platform/windows/platform.rs) & [modal events](https://docs.rs/crate/gpui/0.2.2/source/src/platform/windows/events.rs): candidate executor integration, with native timing/shutdown qualification still required.
