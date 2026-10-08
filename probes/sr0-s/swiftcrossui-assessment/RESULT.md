# SwiftCrossUI runtime core: assessment as an SR0-S seed

Status: read-only research input for maintainers. Not a decision. Evidence is from reading source only: nothing was built, run, or tested. Items marked **[inferred]** are conclusions drawn from code reading rather than observed behaviour.

Scope: SwiftCrossUI core (`Sources/SwiftCrossUI`) and its backend protocol, checked against fixtures F1–F9 of `conformance/sr0-slice/CONTRACT.md` §3 and the Windows runtime list in `docs/architecture.md` §5.

## 1. Header facts

| Item | Value | Evidence |
|---|---|---|
| Source | `https://github.com/moreSwift/swift-cross-ui`, `git clone --depth 1` (default branch at clone time) | scratch clone, not committed |
| Commit SHA | `0f3ec3958b79cdc39a1a3e604516b71ab33a9043` (2026-09-21, "Reorganize DummyBackend into a file per backend feature (#783)") | `git rev-parse HEAD` |
| License | MIT, © 2022 stackotter. Permits forking and redistribution with the notice retained. | `LICENSE` (header read; full text not read) |
| Tools version | `// swift-tools-version:5.10` | `Package.swift:1` |
| Language mode | Swift 5 mode **[inferred]**: tools 5.10 and no `swiftLanguageModes`. The core target enables only `StrictConcurrency` as an upcoming feature. Not Swift 6 strict mode. | `Package.swift:226` |
| Core size | 302 Swift files in `Sources/SwiftCrossUI`. Largest areas: Views ~16.0k lines, Scenes ~3.4k, Backend ~3.5k, Environment ~1.2k, Layout ~1.0k, State ~1.6k, ViewGraph ~0.9k. | `wc -l` on directories |
| Core deps | `swift-observation-polyfill` 0.1.1 (`d8843fa`), `swift-mutex` 0.0.6, `swift-log` 1.14.0; plus `swift-image-formats` and `swift-macro-toolkit` from the manifest. Licences of these dependencies were not checked. | `Package.swift`, `Package.resolved` |
| LLM policy | `LLM_POLICY.md` governs user-generated content on the upstream project (issues, PRs, comments). Rules: disclose LLM usage in PR descriptions; authors must understand submitted code, or document rigorous testing if they do not; PR and issue descriptions must not be written by an LLM (translation tools allowed if disclosed); maintainers may ignore violating PRs. | `LLM_POLICY.md` |
| Forking restriction | None found. The policy covers contributions to the upstream project, not forks or use of the MIT code **[inferred]**. | `LLM_POLICY.md` scope text |
| Upstreaming implication | Any SwiftRight patch offered upstream needs disclosed AI use and a human-written description. A private fork carries no obligation under this policy **[inferred]**. | `LLM_POLICY.md` rules 1, 2, 5 |

## 2. Semantic assessment

"Matches" means matches the SwiftUI behaviour that the SR0 fixtures require. Rewrite size uses none / minor / major / replace.

| Semantic area | SCUI approach | Evidence | Fixture impact | Rewrite size |
|---|---|---|---|---|
| View graph & node model | Each view gets one `ViewGraphNode` that owns a backend widget. Two-phase `computeLayout` then `commit` per node, with a per-proposal cache. Widgets are imperative backend objects; the Swift side owns the tree. | `ViewGraph/ViewGraphNode.swift:9` (class), `:185-257` (computeLayout), `:206-222` (cache reuse), `:265-308` (commit); `ViewGraph/AnyViewGraphNode.swift:6`; `ViewGraph/ErasedViewGraphNode.swift:4` | F1–F3, F5 (retained tree) | **major**: widget-per-node is backend-coupled; a GPUI target needs the §6 commit-transaction ABI, not this call sequence |
| Structural identity | Positional children via `TupleView`/`TupleViewChildren`. | `Views/TupleView.swift`, `Views/TupleViewChildren.swift` (not read line by line) | F3 (reinsert gets fresh state) | none to minor |
| Explicit identity | Only via `ForEach(_:id:)` keypath. No `.id(_:)` modifier exists. Surviving nodes are reused via an identifier map; changed order is applied as widget swaps. Duplicate IDs log a warning and lose state. Non-`Identifiable` without `id` falls back to index-based reuse (deprecated). | `Views/ForEach.swift:4-11`, `:97-101`, `:103-187` (reuse and swap path), `:120-134` (duplicates), `:87-95` and `:207-274` (index fallback), `:409-430` (deprecated inits) | F1, F2: reuse on insert or move is **matches**. Index fallback **mismatches** SwiftUI and must be gated out. | minor (add `ForEach($items)` projection and a `move` path; remove index fallback from the SR0 surface) |
| `ForEach` over `Binding<[Row]>` | Not present. No `Binding`-collection `ForEach` overload was found. | grep of `Views/ForEach.swift`: only `Items: Collection` inits | F1–F3 API | minor (API addition) |
| `@State` storage lifetime | A `Storage` class box lives in a `StateImpl` box. `update(with:previousValue:)` copies the old storage into the new struct, so state persists while the node lives and is dropped with the node. | `State/State.swift:11-46`, `State/StateImpl.swift:9`, `:57-61` | F1 (`@State` unchanged), F3 (fresh on reinsert): **matches** | none to minor. The field lookup uses raw byte offsets and `swift_reflectionMirror_*` runtime symbols (`State/ForEachField.swift:9-16`, `:79-86`; `State/DynamicPropertyUpdater.swift:17-62`), so the mechanism is fragile and should be replaced, not the semantics |
| `Binding` | Closure getter and setter pair. `$projection`, `@dynamicMemberLookup` projection, and `onChange` all exist. A `State`'s projected binding captures the inner storage strongly, so it outlives its node. | `State/Binding.swift:34-76`, `:102-113`, `:121-129`; `State/StateImpl.swift:44-55` | F4: stale write is **possible** (see blocker B3) | minor for the type; the liveness guard for F4 is new (moderate) |
| `@FocusState` / `.focused` | `FocusState` is state-backed. `.focused(_:equals:)` exists, plus a `Bool` overload. Focus is applied at commit via backend widget properties. Tab order is walked over the backend widget graph. Focus identity is widget identity, not model identity. | `State/FocusState.swift:6-52`; `Views/Modifiers/FocusedModifier.swift:8-10`, `:42`; `ViewGraph/ViewGraphNode.swift:271-277`; `Backend/BackendHelpers.swift:33-40`; `Backend/FocusChainManager.swift:11-118` | F1, F2, F8: focus follows widget, so it survives reuse, but caret and model-identity focus are not modelled | major for the GPUI focus target; the `.focused` API surface is reusable |
| `@Environment` | `EnvironmentValues` is a struct passed down by parameter. `@Environment(\.key)` reads on `update`. Custom `EnvironmentKey` works. Reading before `body` traps. | `Environment/Environment.swift:39-103` (`:63-70` trap), `Environment/EnvironmentValues.swift:66`, `:513` (`EnvironmentKey`) | Custom key in slice: **matches** | none to minor |
| Observation | `ModelObserver.observe` wraps body evaluation in `ObservationPolyfillCore.withObservationTracking`. On change it calls `backend.runInMainThread` (async), with a per-observation ID to dedupe. `@Observable` goes through `ObservationPolyfillCore`. The source says that on Windows this is the stdlib `Observable` underneath **[inferred from comment]**. The polyfill re-export is Apple-only. | `State/ModelObserver.swift:51-67`; `State/Observation.swift:1-2`; `State/State.swift:74-89` (`:82-84` comment) | `@Observable` per SR0: **matches** in spirit (re-run whole body per changed view). Needs explicit `import Observation` on Windows. | minor |
| Combine-style `ObservableObject` | Supported. `ObservableObject` conformance is discovered by `Mirror` reflection on each `didChange` access. `State` accepts `ObservableObject`. `@StateObject`, `@ObservedObject`, `onReceive` were not found in grep. | `State/ObservableObject.swift:60-88`; `State/StateImpl.swift:22-33`; grep for `StateObject`, `ObservedObject`, `onReceive` returns none | Negative fixtures: `ObservableObject` **must be compile-gated**, since SCUI accepts it | minor (gate) |
| Update scheduling & coalescing | `Publisher.send()` is synchronous. UI updates go through `observeAsUIUpdater`: a semaphore admits one pending update and merges the rest, the action hops to the main thread via `runInMainThread`, and a `Thread.sleep` throttle runs on a dispatch queue. Updates are coalesced and dropped. | `State/Publisher.swift:34-38`, `:97-160` (`:106-115` merge, `:143-156` sleep), `:15` (`@unchecked Sendable` stats) | F1–F4, F6: order and completion are not deterministic; merging drops intermediate transactions. The sleep is a Gtk3 heuristic. | major (replace with an explicit main-actor update loop) |
| Transactions | None. No transaction type, no `withTransaction`. | grep for `Transaction` in `Sources/`: none | F6: **absent** | major |
| Animation | None. `withAnimation`, `.animation(_:value:)`, reduced-motion environment are all absent. Only backend-specific `animated:` calls in AppKit and UIKit backends. | grep for `animat` (case-insensitive) in `Sources/SwiftCrossUI`: no core hits | F6: **absent** (greenfield) | replace (new subsystem) |
| `onAppear` | Action runs inside `asWidget`, i.e. during node construction and before the widget is attached to its parent. | `Views/Modifiers/Lifecycle/OnAppearModifier.swift:11-24` (`:24` `action()` in `asWidget`); `ViewGraph/ViewGraphNode.swift:106` (`asWidget` called in `init`) | F3: **timing mismatch** (appear before attach) | moderate |
| `onDisappear` | Fires from `deinit` of a children object, which spawns a `Task { @MainActor }`. Teardown is ARC-timed and asynchronous. | `Views/Modifiers/Lifecycle/OnDisappearModifier.swift:84-108` (`:104-107`) | F3 ordering, F9: **mismatch** (blocker B2) | major (explicit unmount pass) |
| `task` & cancellation | `TaskModifier` keeps the `Task` in `@State`, starts it via `onChange(initial: true)`, and cancels it on `onDisappear`. Cancellation depends on the async `onDisappear` above. | `Views/Modifiers/Lifecycle/TaskModifier.swift:46-65` (`:57-64`) | F4: cancel is **late**; stale results are not blocked (B3) | moderate (after teardown is fixed) |
| `onChange` | The action runs inside `computeLayout`, so it can fire during speculative layouts that the cache may repeat. | `Views/Modifiers/Handlers/OnChangeModifier.swift:33-45`; `ViewGraph/ViewGraphNode.swift:206-222` | Side effects in layout: affects F4, F6 determinism | moderate (move side effects to commit) |
| Layout ownership & proposals | Swift owns sizes and positions; backend gets `setSize` and `setPosition` as integer `SIMD2<Int>`. `ProposedViewSize` uses `nil` for unspecified. Stack layouts are internal (`computeStackLayout`). `roundSize` rounds up to `Int`. | `Layout/ProposedViewSize.swift:2-38`; `Layout/ViewLayoutResult.swift:2-65`; `Layout/LayoutSystem.swift:10-23`, `:110`; `Backend/BackendFeatures/Core/Widgets.swift:55`, `:71`; `Backend/BackendFeatures/Core/GenericContainers.swift:41` | Swift-owned layout: **matches** the architecture rule (§5). Integer rounding: **mismatch** for exact geometry (B7) | major for the geometry type (`Double`, exact bounds); minor for stack logic |
| Custom `Layout` protocol | Absent. No `Layout`, `sizeThatFits`, `placeSubviews`, `Subviews`, `LayoutValueKey`. Only `GeometryReader` (`Views/GeometryReader.swift:21-116`). | grep for `protocol Layout`, `sizeThatFits`, `placeSubviews`: none | F5: **absent** | major (add protocol and subview size queries) |
| Text measurement | Synchronous `backend.size(of:whenDisplayedIn:proposedWidth:proposedHeight:environment:)` returns `SIMD2<Int>`. The call sits inside `computeLayout`, and `updateTextView` runs there too. No baselines, no shaped-run handle. | `Views/Text.swift:72-123` (`:78-85`); `Backend/BackendFeatures/PassiveViews/TextViews.swift:49-58` | F5, F7 need baselines and handle-based cache per contract §6 | major for the ABI; the size-only shape is reusable |
| Text input & selection | `TextFields` is string get and set plus `onChange` and `onSubmit`. `TextField` pushes its binding into the widget on each commit when they differ. No caret, selection range, marked text, or undo in the protocol. `TextEditors` is the same. | `Backend/BackendFeatures/Controls/TextFields.swift:6-46`; `Views/TextField.swift:103-143` (`:137-140`); `Backend/BackendFeatures/Controls/TextEditors.swift:6-43`; grep for `caret`, `marked`, `preedit`, `selectedRange`: no core hits | F1, F2 (caret), F7 (IME): **absent** (B4) | replace (new text-input model, Swift and native sides) |
| `List` & selection | `List(data, id:, selection:)` with `Binding<SelectionValue?>`. `SelectableListViews` backend protocol. No `onMove` or `onDelete`. | `Views/List.swift:8-27` and following; `Backend/BackendFeatures/Containers/SelectableListViews.swift:6-77` | F2: `onMove` **absent**; move ops reuse the ForEach swap path | minor for the list; moderate for move APIs |
| Windows & scenes | `Window` scene creates a `ViewGraph`. Close sets the `windowReference` to `nil`, releasing the graph. No explicit cancellation or post-close commit guard. | `Scenes/Window.swift:61`, `:94`; `Scenes/WindowGroup.swift:67`, `:104`; `Scenes/WindowReference.swift:34-64` | F9: ARC-driven teardown; cancellation and "no commit after close" **absent** | moderate |
| Threading & isolation | Views, graph nodes, and backend protocols are `@MainActor`. `Publisher` is not actor-isolated (dispatch queue and semaphore). `runInMainThread` is `nonisolated`. Core is Swift 5 mode with `StrictConcurrency` as an upcoming feature. | `Views/View.swift:2-3`; `ViewGraph/ViewGraph.swift:10`; `ViewGraph/ViewGraphNode.swift:8`; `Backend/BackendFeatures/Core/Widgets.swift:4-5`; `Backend/BackendFeatures/Core/Core.swift:15-16`, `:75`; `State/Publisher.swift:15`, `:25-28`; `Package.swift:226` | SR0 requires Swift 6 strict concurrency: **migration needed** | moderate (language mode migration plus scheduler rewrite) |
| Accessibility | Absent in core and in the backend protocol. The only "accessibility" hit is a help-text doc comment. No role, label, action or value model. | grep `accessibility`, `AccessKit`, `AXRole`: only `Views/Modifiers/HelpModifier.swift:7` | F8: **absent** (B6) | replace (contract §5 requires a semantic tree and AccessKit mapping) |
| Entry | `App.main` calls `Backend.earlySetup()`, then `_App.run()`. `Core.runMainLoop(_:)` takes a callback the backend invokes. Shape is close to a synchronous initial-thread entry. | `App.swift:148-160`; `Backend/BackendFeatures/Core/Core.swift:17-63` | Entry requirement: **roughly matches**; initial-thread identity is not checked | minor |

## 3. Fixture matrix (F1–F9)

| Fixture | SCUI state | Verdict |
|---|---|---|
| F1 surviving-row identity | Reuse on insert via `ForEach` id map; `@State` persists. No caret or focus-by-model-identity. | partial: caret assertion fails |
| F2 reorder | Swap-based reorder keeps nodes. No `onMove`. Caret not modelled. | partial |
| F3 removal / reset | Reinsert gets fresh `@State`. Teardown is async and ARC-timed. `onAppear` fires before attach. | fails ordering as specified **[inferred from code]** |
| F4 stale async | No liveness guard. Bindings keep storage alive, so late writes can land. | fails |
| F5 width layout (custom Layout) | No `Layout` protocol. Integer geometry. | fails |
| F6 interrupted animation | No transactions and no animation. | fails (absent) |
| F7 IME | No marked text. Binding-to-widget sync can overwrite composition **[inferred]**. | fails (absent) |
| F8 accessibility | No semantic model. | fails (absent) |
| F9 window teardown | ARC release on close; no explicit cancellation or commit guard. | fails |

## 4. Blocking semantic mismatches

These block SR0 fixtures as written in the contract. Each needs runtime work, not only a compile gate.

- **B1. Update scheduling is coalesced and asynchronous.** Updates are merged and dropped, and they hop threads with a sleep throttle (`State/Publisher.swift:97-160`; `Backend/BackendFeatures/Core/Core.swift:75`). No transaction exists. Breaks F6 and deterministic replay for F1–F4.
- **B2. Teardown is ARC-driven and asynchronous.** `onDisappear` fires from a `deinit` that spawns a `Task` (`Views/Modifiers/Lifecycle/OnDisappearModifier.swift:104-107`). Task cancellation chains through it (`Views/Modifiers/Lifecycle/TaskModifier.swift:62-64`). Breaks F3 ordering and F9.
- **B3. Stale writes after teardown are possible.** A `Binding` captures the inner storage strongly (`State/StateImpl.swift:44-55`; `State/Binding.swift:54-56`). Nothing checks whether the owning node is still live. Breaks F4 ("result not committed to any row").
- **B4. No caret, selection, or marked text.** `TextFields` is a string sync with no range or composition state (`Backend/BackendFeatures/Controls/TextFields.swift:6-46`). `TextField` writes binding content back to the widget on commit (`Views/TextField.swift:137-140`). Breaks F1 and F2 caret assertions and F7 IME **[inferred for IME]**.
- **B5. No animation or transaction model.** Absent (grep). Breaks F6 entirely.
- **B6. No accessibility model.** Absent in core and in the backend protocol. Breaks F8.
- **B7. Integer geometry and no `Layout` protocol.** `roundSize` rounds up to `Int` (`Layout/LayoutSystem.swift:10-23`), and backend geometry is `SIMD2<Int>` (`Backend/BackendFeatures/Core/Widgets.swift:55`, `:71`). Breaks F5's "paint = hit-test = AX bounds" if that means exact physical-pixel geometry **[inferred from contract §6]**.

Non-blocking but must change: `onChange` side effects inside `computeLayout` (`Views/Modifiers/Handlers/OnChangeModifier.swift:33-45`); index-based `ForEach` fallback (`Views/ForEach.swift:87-95`); `ObservableObject` support that the negative fixtures must reject; the reflection-based state lookup (`State/DynamicPropertyUpdater.swift:17-62`); Swift 5 language mode.

## 5. Backend protocol summary

- Composition: `BaseAppBackend = Core & Containers & PassiveViews & Controls` (`Backend/BaseAppBackend.swift:15-19`). `FullAppBackend` adds about 20 more feature protocols (`Backend/FullAppBackend.swift:29-51`).
- `Core` (`Backend/BackendFeatures/Core/Core.swift:15-94`): `init()`, `deviceClass`, `earlySetup` (default), `runMainLoop(_:)` (callback), `runInMainThread` (nonisolated), `computeRootEnvironment`, `setRootEnvironmentChangeHandler`.
- `Widgets` (`Core/Widgets.swift:4-72`): `show`, `showUpdate` (default), `tag` (default), `naturalSize` (`SIMD2<Int>`), `setSize` (`SIMD2<Int>`).
- `CoreWindowing` (`Core/CoreWindowing.swift:5-170`): create, update, title, child, size, size limits, resize and environment-change handlers, show, activate. Plus `supportsMultipleWindows` and related flags.
- `GenericContainers` (`Core/GenericContainers.swift:5-48`): `createContainer`, `removeAllChildren`, `insert`, `swap`, `setPosition` (`SIMD2<Int>`), `remove`.
- `TextViews` (`PassiveViews/TextViews.swift:6-70`): `size(of:whenDisplayedIn:...)`, `createTextView`, `updateTextView`.
- `TextFields` (`Controls/TextFields.swift:6-46`): `createTextField`, `updateTextField` (placeholder, environment, `onChange`, `onSubmit`), `setContent`, `getContent`.
- Other controls: `TextEditors`, string- and view-label buttons (`Controls/Buttons.swift`), toggles, sliders, pickers, progress, secure fields, and more under `Controls/`.
- Containers: `ScrollContainers`, `SelectableListViews` (`Containers/`).
- Focus: `FocusHandling` (`FocusHandling.swift:9-27`): `registerFocusObservers`, `setFocusEffectDisabled`, `setFocus`. `FocusDisabling` adds focus containers.
- Windowing, menus, sheets, alerts, file dialogs, tables, gradients, web views, colour pickers, date pickers: present in `FullAppBackend` and outside the SR0 slice.
- Defaults: `Backend/BackendFeatures/BaseStubs.swift` (567 lines) supplies placeholders for unimplemented features. Doc comment says they fail when called (`Backend/BackendFeatures.swift:6-9`).
- Size: roughly 150 requirement lines across `BackendFeatures`, grep-approximate, including some defaulted methods.
- What a GPUI backend would have to do **[inferred]**: implement a widget-object protocol with imperative insert, remove, swap, and position calls, plus a text-field protocol with no caret, selection, or composition. The §6 ABI (commit transactions, geometry, primitive lists, semantic nodes, IME events) would sit underneath as a bridge. That bridge is a major piece, and most of the SR0 risk lives in it.

## 6. Recommendation (evidence for maintainers)

- The reusable parts are narrow: the state box carried across updates (`State/StateImpl.swift:57-61`), `ForEach` keyed reuse with swap-based reorder (`Views/ForEach.swift:103-187`), `Binding` and `Environment` shapes, the `.focused` API, and the proposal and cache model (`ViewGraph/ViewGraphNode.swift:185-257`). These map to minor edits plus the Swift 6 migration.
- The areas that decide the SR0 outcome are absent or conflict with fixtures: scheduler (B1), teardown (B2), stale-write guard (B3), text input (B4), animation (B5), accessibility (B6), geometry (B7). Most of the code for these would be rewritten rather than adapted.
- The backend protocol is an imperative widget API. The architecture's §6 commit-transaction ABI would replace it, so the protocol is replaced rather than extended.
- **Evidence leans toward the fresh runtime** for the scheduler, lifecycle, layout geometry, text, animation, and accessibility. A fork would carry SCUI's scheduling and layout paths into the SR0 blockers. SCUI's identity, state, binding, and environment code is worth reading as a reference, and MIT permits copying it with notice.
- This is a comparison input, not a decision. Maintainers should confirm the F3 ordering against the Mac recording and the F5 exact-geometry requirement before weighing it.

## 7. Gaps in this assessment

- Not built, not run, no test suite executed. Tests are 12 files under `Tests/SwiftCrossUITests`.
- Dependency licences (`swift-observation-polyfill`, `swift-mutex`, `swift-log`) were not checked.
- `LICENSE` header only; full text not read.
- Windows behaviour of the Observation polyfill is taken from a source comment **[inferred]**, not tested.
- `Timer.publish` was not checked for absence.
- `Views/TupleView*.swift` and `Views/Modifiers/*` were grepped, not read line by line.
