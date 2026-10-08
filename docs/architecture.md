# SwiftRight: one Swift codebase, real SwiftUI on Mac, SwiftUI-semantics runtime on Windows

Architecture v0.4 — 8 October 2026

Status: proposed architecture; no implementation or measured performance claimed. v0.4 retains real SwiftUI on Mac & an owned SwiftUI-semantics runtime on Windows, with GPUI as first renderer candidate. It corrects dependency evidence, layout ownership, oracle design, decision gates & workspace integration. Review history & finding dispositions are in [architecture-review.md](architecture-review.md).

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

GPUI evidence must distinguish published artifacts from upstream source. Published `gpui 0.2.2` contains no AccessKit dependency or integration. Upstream source inspected at `b47a4ca595d3a3fba116b9e78ef01a46e2e43f3e` includes AccessKit & a Windows adapter; its GPUI manifest still says `0.2.2`, so that version string does not identify equivalent contents. AccessKit integration merged upstream on 27 May 2026. GPUI remains pre-1.0, Apache-2.0, with frequent breaking changes. [S19, S25, S26]

No accessible renderer distribution is selected by this plan. SR0-D must identify an exact consumable distribution, its source revision, lockfile, features, licences & artifact hashes, then exercise its Windows UI Automation surface. A dependency declaration, upstream example or Zed release does not qualify SwiftRight's controls. Published `gpui 0.2.2` alone cannot satisfy this prerequisite.

Prior SwiftUI reimplementations set expectations. Tokamak, a SwiftUI-compatible framework for other renderers, was archived in January 2026 after covering a basic subset. OpenSwiftUI, the most complete independent implementation, still lists its cross-platform attribute graph as incomplete and text unsupported off Darwin, after years of work. Full SwiftUI parity is therefore scoped by inventory and oracle, never promised whole. [S7, S21]

SwiftCrossUI is a Swift SwiftUI-like runtime with a backend protocol and seven backends; its semantics are its own and it disclaims SwiftUI compatibility. Its WinUI backend sits on an archived binding lineage with an open UI Automation crash; v0.3 no longer depends on it. Its runtime core remains a candidate seed for SwiftRight's runtime, compared in SR0 against a fresh implementation. [S3, S4, S14, S15, S16]

Slint is an alternative renderer candidate. Its platform API adapts Slint scenes to operating-system services; it does not establish that SwiftRight's retained tree can be rendered unchanged. Before fallback selection, prove dynamic tree updates, runtime-owned layout, text measurement, IME & accessibility through SwiftRight's ABI, plus distribution rights for an SDK. No Slint version or drop-in compatibility is assumed. [S22, S23, S27]

Swift–Rust interop has no official bridge. C ABI is supported by both languages; `swift-bridge` generates typed bindings over it. Either is work SwiftRight owns and tests. [S24]

An October 2026 spike shipped Swift 6.3 code as a `@c` DLL on Windows x64 and arm64 and established two reusable facts: Foundation ICU alone is ~37 MB, and Swift main-actor work only runs when the main dispatch queue is pumped from the host UI loop. [S18]

## 3. Architecture decisions

**AD1 — Unmodified toolchains.** Released Swift and Rust toolchains, Swift Package Manager, Cargo, supported platform SDKs. Pin a tested compatibility matrix.

**AD2 — One codebase, two implementations of SwiftUI's programming model.** On macOS, SwiftRight types are SwiftUI's types. On Windows, SwiftRight owns identity, state lifetime, dependency tracking, bindings, environment, layout proposals, transactions & lifecycle, rendering through a versioned C ABI. GPUI is first candidate; Slint is an alternative only after passing that ABI's conformance slice. Backend interchangeability is a qualification result, not an assumption. Application source & public semantics remain fixed during comparison. A second-language shell is never the fallback.

**AD3 — App-level state is portable; native objects are not.** Shared domain logic cannot depend on SwiftUI, AppKit, GPUI, React or Tauri. Swift runtime owns screen identity, edit state & focus intent; backend owns OS focus integration, window handles & renderer resources.

**AD4 — Existing engines survive.** Keep working Rust/C/C++ services. Add a versioned service boundary and replace the shell incrementally. On Windows the engine may link in-process with the renderer crate when that simplifies the app.

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
    SwiftRightUI/          # public API; Mac target (SwiftUI) and Windows target (runtime + bridge client)
    SwiftRightServices/    # service contracts; Mac and Windows targets
    SwiftRightTesting/     # conformance fixtures, trace recorder (Mac), trace replayer (Windows)
  render/
    swiftright-render/     # Rust crate: backend protocol server, GPUI backend, AccessKit mapping
    swiftright-abi/        # C header + generated Swift/Rust bindings, versioned
  prebuilt/                # pinned renderer artifacts per OS/arch, reproducibly built
  scripts/                 # thin RightKit calls, trace candidates, local qualification
  examples/
    ControlsGallery/
    DesktopUtility/
    EngineClient/
  conformance/
  benchmarks/
  docs/
```

Three shipping Swift packages, one testing package & two Rust crates in v1. Split further only when a second consumer needs it.

## 5. SwiftUI on Mac, SwiftUI semantics on Windows

**macOS.** `SwiftRightUI.View`, `State`, `Binding`, `Environment`, and inventory modifiers are SwiftUI's own types. A thin adapter is allowed where it is itself a SwiftUI view and preserves composition and identity. Xcode previews, third-party SwiftUI packages, and the AppKit escape hatch stay intact. Consequence: every SwiftUI API compiles on Mac; only Windows compilation and conformance replay prove inventory membership.

**Windows.** The SwiftRight runtime implements SwiftUI's programming model, not its syntax alone:

- View identity: structural position plus explicit `id`, stable across insert, delete, filter, reorder.
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

SR0's custom `Layout` fixture is a feasibility probe, not a claim of full protocol coverage. Expansion milestones: virtualization, tables, navigation, multiple windows, drag/drop, broader `Layout` support & gestures. Document editors, canvas systems, and media timelines do not shape the first release.

### Compatibility categories

- **Inventory:** same source, same traced behaviour on both platforms.
- **Adapted:** same intent with a documented presentation difference (menu placement, control metrics, Fluent theming).
- **Platform extension:** intentionally Mac-only or Windows-only module.
- **Unsupported:** fails at Windows compile time.

## 6. State, identity, layout, events, threading

**Domain state.** Ordinary Swift values, explicit commands and effects, actors where isolation is required, stdlib `Observation` on both platforms, macOS 14 floor.

**Identity and lists.** Tests insert, delete, filter, and reorder rows while selection, caret, and IME composition are active. Losing the caret or binding an edit to the wrong row fails the build even when screenshots look right.

**Layout authority.** Swift owns proposals, alignment, placement, scroll geometry & final hit-test bounds. Rust owns font shaping, glyph rasterization & intrinsic native metrics. Measurement is a synchronous, read-only C ABI query on Windows' UI thread, before frame commit; it returns size, baselines & an explicitly retained shaped-run handle. It cannot call Swift, pump tasks, change tree state or wait for work scheduled on that same thread. Cache keys include text, font/version, proposed width, locale, direction & DPI. Measure requests are batched where possible; all crossings count toward §11 budgets.

Swift commits geometry, text-run handles, focus target & accessibility-node changes as one versioned transaction. Rust paints & hit-tests that snapshot without changing placement. Events identify window generation, node identity & snapshot version; stale events cannot edit a reused row or closed window. Rust reports OS text/IME events; Swift owns editable buffer, selection, undo & composition state, returning current caret geometry to Rust's OS adapter. A width-dependent text fixture verifies that measured, painted, hit-tested & accessible bounds agree before ABI v0 is frozen.

**Events and tasks.** Specified ordering, cancellation, coalescing, and teardown. A closed window must not retain its element tree through an unbounded stream or engine callback.

**Threading and the bridge.** Rust owns Windows' UI event loop & rendering resources. Swift's main actor runs on that UI thread through a tested dispatch integration; it is never pumped recursively during measurement or commit. Verify wake-up, cancellation, idle behaviour & queue fairness under load, including while windows are closing. Bridge rules: opaque generation-tagged handles, explicit retain/free & buffer lifetimes, batched frame commits, bounded queues with declared overflow errors, typed failures & no Swift closures across ABI. Rust panics never unwind into Swift; distinguish recoverable errors from process termination, including aborting builds. SR0 injects stale handles, queue overflow & teardown races. UI-only changes reuse unchanged Rust artifacts; linking is measured separately from rebuilding them.

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

## 8. Retaining Rust engines

Default migration path: Swift client adapters over RightKit-owned process & transport capabilities, communicating with existing Rust engines through inherited pipes or user-restricted sockets/named pipes. Preserve handshake, version range, correlation, timeouts, queue bounds, typed errors, shutdown & reconnect; implement only application protocol mapping in SwiftRight. Required shared-package feature gaps stay with their owner.

On Windows, the engine may instead link into the same process as the renderer crate and expose the same versioned protocol in-process. Choose per app by measurement; keep the out-of-process path as rollback.

High-rate data (audio, frames, inference) stays inside the engine. Exchange commands, transcripts, status, and bounded progress with the UI. Never route raw frames through JSON.

In-process C ABI between Swift and Rust follows the bridge rules in §6: ownership, opaque handles, error values, thread rules, buffer lifetimes, panic containment.

## 9. Tooling and distribution

No bespoke CLI in v1. Swift Package Manager builds Swift; managed `rightkit cargo` builds Rust on each native host. Xcode serves Mac development & SourceKit-LSP Windows. Repository scripts are thin qualification/RightKit callers. Swift Bundler may supply unsigned app preparation where compatible; it does not own signing or installer machinery.

**Prebuilt renderer.** SR0-D selects an exact published renderer dependency set containing required accessibility support; a newer upstream Git checkout is not a substitute for an available distribution. Record package checksums, source revisions, licences, lockfile, feature set, native target & build recipe. Build `swiftright-render` on native Windows x64 & arm64 hosts through managed RightKit, with artifact digests bound to those inputs. A second build checks reproducibility of unsigned payloads; signing evidence binds final artifacts separately. Swift consumers reuse these artifacts; a screen-only edit must invoke no Rust compilation.

**Pinned tuple.** Swift/Rust toolchains, macOS runtime build, Mac SDK/Xcode, Windows runtime/SDK, architecture, GPU/driver, renderer distribution & source revision, AccessKit revision, features, bridge ABI, SwiftRight & engine protocol. Benchmark metadata also pins fonts, locale, DPI, power mode & display refresh. An SDK version alone does not identify SwiftUI runtime behaviour.

**Packaging.** RightKit `right-release` owns native build/sign/package/seal mechanics. Apple & Azure signing are provisioned; no enrollment or signer setup gate is needed. Mac inputs are app bundle, resources & entitlements. Windows target is MSIX with package identity & an explicit Swift runtime dependency inventory from selected toolchain. Prove clean-machine loading; do not assume future static-stdlib support. A missing Swift/MSIX adapter is a shared-tooling gap, not permission to implement signing/installer scripts here. Clean-machine install, uninstall, upgrade, interrupted/failed update & first-launch permissions are required on both OSes.

**Execution hosts.** This private `bogusyogi` repository uses provisioned local native Mac, Windows x64 & Windows arm64 hosts. No GitHub Actions workflows or billed runners. SR0-D records actual availability; a missing native architecture blocks its qualification instead of being replaced by cross-compilation. Builds, tests & signing run on their target host. Build/seal remains separate from publication; private product uploads use configured RightKit/R2 delivery only when requested. Workspace runbooks: `docs/rules/rightkit.md`, `docs/rules/github-access.md`, `docs/rules/release-signing.md` & `docs/RIGHTKIT-SHARED-PLATFORM.md` in `bogusyogi/claude`.

## 10. First consumers and migration

Begin with a real desktop utility/settings screen: persistent state, editable text, a list, tray entry, shortcut, dialog, releasable package.

For HeardRight-like functionality: settings or command history against the existing engine first, then resident/tray behaviour, then overlay/audio workflows.

Keep the current app functional while adding the new shell behind a development/release option. Preserve file formats and IPC semantics. Migrate one complete feature at a time. React/TypeScript screens are rewritten once into SwiftUI; thereafter one source serves both platforms.

RustRight's CLI must not depend on this SDK; the SDK must not require RustRight to build.

## 11. Conformance and performance

Three test layers: inventory contract tests, platform interaction tests, complete application tests.

### Executable oracle contract

Fixtures replay input stimuli, never recorded output state. Each inventory entry identifies exact APIs/overloads, supported compositions, initial state, stable node IDs, stimulus sequence, observable assertions & unsupported compile cases. Fixture metadata binds source hash, trace schema, pinned platform tuple & adaptation rules.

- **Stimuli & scheduling:** timestamped keyboard, pointer, focus & text-composition actions plus application effect completions. Inject fixture clocks & fake engine responses into app-owned work; control when async results become available. Do not assume control over SwiftUI's private scheduler. Specify required event partial orders, observable settlement conditions & timeouts instead of matching incidental callback timing.
- **Observations:** state, identity, selection, caret/composition, focus, layout & accessibility; instrument public lifecycle callbacks, effect start/cancel/complete & committed side effects. Deliver late completions after cancellation & window closure; they must neither mutate current state nor reach destroyed views. Record animation interruption/completion & reduced-motion outcomes, not just endpoints.
- **Normalization:** compare exact semantic values & stable identity. Canonical accessibility nodes preserve role, label, value, supported actions, focus & meaningful parent/child order. Strip only named platform-generated containers/IDs. Keep native trees for debugging. Every adapted entry names allowed metric/presentation differences & bounds; no blanket timing or geometry tolerance. Layout assertions include containment, clipping, minimum hit targets, caret visibility & agreement between paint, hit-testing & AX/UIA bounds.
- **Repeatability:** run each Mac fixture 20 times on its pinned runtime. All normalized semantic assertions & required orderings must agree before it becomes an oracle. Variance becomes an explicit permitted ordering or fixture defect. Windows then executes identical stimuli & assertions. Inject wrong row identity, a stale task commit & a missing accessibility action to prove comparator rejects each fault.
- **Native interaction:** recorded logical IME actions test runtime state; real OS IMEs, Narrator/NVDA & keyboard navigation separately test platform integration. Neither substitutes for the other. Native checks verify actions affect intended model state, beyond merely exposing controls.
- **Change control:** retain accepted traces, assertions & environment metadata. New OS/toolchain observations create candidate baselines; compare them against accepted expectations before adoption. Automation cannot bless drift by regenerating expected output.

Cover state and binding lifecycle, focus, undo/redo, Unicode and IME, keyboard-only use, accessibility roles/labels/actions through UI Automation on Windows and the accessibility API on macOS, right-to-left, high contrast, reduced motion, DPI scaling, multi-monitor, window reopen, subscription teardown.

**Windows accessibility gate.** A UI Automation walk of every shipped window completes and exposes every control; Narrator and NVDA activate inventory controls. Screen-reader failure is a release blocker.

### Decision budgets

These are initial engineering acceptance limits, not measured results or upstream guarantees. Freeze them with SR0-C fixtures before either seed is scored. Mac & Windows have separate records; Windows x64 success cannot qualify arm64. Any later limit change requires a documented contract revision & rerun of both candidates on the same workload.

SR0 workload: 200 stable-ID editable rows, 20 asynchronous row updates/inserts per second, one reorder per second, continuous scrolling & editing, with fixed-size data maintained by removing unrelated rows. Include width-dependent text layout, interrupted animation, cancellation & window teardown. Pin logical window size, fonts, DPI, input script & 60 Hz display. Use release builds without debugger; after 10 seconds of warm-up, collect three 60-second runs. Every run must pass; archive raw samples & report p50/p95/p99. IME & screen-reader correctness scenarios run separately with native tools.

| Measurement | SR0 pass condition |
|---|---|
| Identity, text edits, cancellation & accessibility actions | Zero wrong-node edits, lost commits, post-cancellation state commits or missing required actions |
| Windows bridge handling per input event | p95 ≤ 1 ms; p99 ≤ 2 ms |
| Windows aggregate bridge time per committed frame | p95 ≤ 2 ms; p99 ≤ 4 ms, including synchronous measurement, encoding, copying & commit; do not double-count nested calls |
| End-to-end input to visible response, each OS | p95 ≤ 50 ms; p99 ≤ 100 ms; include all queueing & frame waits |
| Frame presentation interval during continuous animation/scroll | p95 ≤ 16.7 ms; p99 ≤ 33.4 ms on fixed 60 Hz display |
| Swift main-actor enqueue to execution on Windows | p99 ≤ 16.7 ms under slice load; no deadlock or starvation |
| UI-only incremental build | Zero Rust compiler invocations; renderer & unchanged engine artifact hashes stay identical |

For SR2/SR4, measure same feature & engine in existing React/Tauri shell on each reference machine before migration. Freeze baseline package size, process-tree memory, CPU wakeups & startup-to-interactive. Initial non-regression limits: startup p95, steady-state process-tree memory, idle wakeups & shipped bytes each ≤ 110% of that OS baseline; screen-only incremental build median ≤ baseline, using 10 edits per shell. Startup uses 30 fresh process launches with cache state recorded; memory uses three 60-second steady-state samples; idle wakeups use three 60-second idle samples. Missing comparable baseline blocks that performance claim. Both platforms must still pass absolute interaction limits above; no predicted Mac win counts as evidence.

## 12. Delivery gates

**SR0 — Decision slice.** One feature through Apple SwiftUI & Windows: an editable, reorderable list with an async insert above active edit; width-dependent custom `Layout`; interrupted animation; async cancellation; keyboard/IME editing; accessibility inspection & activation. Restrict both seeds to identical slice inventory. Each stage below has a pass/fail result; later stages cannot treat an earlier missing prerequisite as passed.

| Stage | Deliverable & required result | Depends on |
|---|---|---|
| SR0-D: dependencies & hosts | Select exact available renderer distribution with AccessKit; record native x64/arm64/Mac hosts, RightKit owner/adapter map, toolchains & package checksums. Run minimal renderer window through UIA discovery & action on both Windows architectures. Missing distribution/host or failed native gate blocks GPUI-dependent work. | None |
| SR0-C: slice contract | Freeze exact slice APIs, inputs, expected effects, normalized assertions, negative fixtures & §11 budgets. Define public subset of custom `Layout` required by probe. | None; may run alongside D |
| SR0-O: oracle & comparator | Run Mac recorder repeatedly; pass repeatability. Build comparator & replay-driver skeleton before seed selection; prove deliberate semantic faults fail. Windows runtime results arrive at S. | C |
| SR0-B: bridge & measurement | Prove runtime-owned layout with a hand-authored tree, width-dependent text, coherent paint/AX bounds, non-reentrant main-actor pumping, bounded queues & teardown. Build native x64/arm64 prebuilt artifacts & freeze ABI v0 only after this probe. | D, C |
| SR0-S: seed comparison | SwiftCrossUI-core fork candidate & fresh runtime execute frozen slice through same qualified backend. Both run compiler checks, oracle assertions, native IME/UIA actions & budgets on each target; select only a fully passing seed. Among passing seeds, prefer fewer semantic overrides & lower measured bridge/runtime cost. | O, B |
| SR0-P: packaged qualification | RightKit produces signed Mac app & signed Windows MSIX. Clean machines install, launch offline, upgrade, reject corrupt updates, recover interrupted updates & uninstall. Verify all runtime dependencies, per-arch artifacts & unchanged Rust binaries after a Swift-only edit. | Selected passing S; shared packaging adapters available |
| SR0-A: repeatable automation | Local native qualification jobs replay accepted fixtures, propose trace/pin updates in candidate lane & exercise UIA. Emit structured stage-start/pass/fail output with artifact/fixture identity. SR0 closes only when D through A pass. | P |

One initial attempt & at most one targeted repair per failing stage/candidate. Repeated failure ends that candidate's SR0 attempt; record failing fixture, layer & evidence before changing direction. Do not reset retry counts by renaming a stage or switching renderer. Missing prerequisites stop dependent work immediately. This gate sequence replaces v0.3's calendar deadline; no delivery ETA is asserted before dependency & host qualification.

### Failure-specific fallback

| Failure owner | Required disposition |
|---|---|
| Distribution, licence, native host or packaging prerequisite | Resolve through existing owner or mark candidate unavailable; no fake qualification, ad hoc signer or billed private CI |
| Oracle repeatability or comparator | Repair fixture/normalization within stage cap; seed selection stays blocked |
| Runtime identity, binding, task lifetime or layout semantics | Repair/reselect seed against unchanged fixtures; if neither passes, stop SDK expansion & retain existing app |
| Bridge latency, queueing, lifetime or dispatch | Isolate cost with same input/tree; repair ABI/batching/threading within cap, then rerun affected stages for both seeds. Renderer swap alone is not resolution |
| GPUI-specific painting, intrinsic measurement, OS IME or accessibility | Slint may replace GPUI only after evidence locates defect in backend & alternative qualifies below |

IME & accessibility failures require layer diagnosis: wrong composition state or missing semantic action can originate in Swift runtime, not renderer. For any alternative, first settle SDK redistribution rights, then run same dynamic-tree, measurement, focus, IME, accessibility & latency probes on both Windows architectures. No transpiler or second application shell is allowed. A backend qualifies only if application source & public contract stay unchanged; required ABI changes reopen B & all downstream gates. Until Slint passes, it is an unqualified candidate, not an available recovery path.

**SR1 — Inventory contract.** Initial inventory with fixtures, traces, replays. Unsupported APIs fail at Windows compile. List identity, binding, focus, cancellation, teardown pass before adding controls.

**SR2 — Desktop utility.** Complete internal utility with persistence, menus/tray, shortcuts, dialogs, installer per OS. Error paths verified.

**SR3 — Engine-backed feature.** One real feature through the shell against an existing engine, in-process on Windows if measured better. Tests cover crash, restart, incompatible protocol, cancellation, stale events, rollback.

**SR4 — Production performance and reliability.** Budgets met, clean-machine install and update, platform differences documented. A Mac regression blocks release even when Windows passes.

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
