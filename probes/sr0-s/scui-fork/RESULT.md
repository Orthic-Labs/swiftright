# SR0-S second seed: SwiftCrossUI-core fork (headless)

Not committed, no branch, headless only. Everything written under `probes/sr0-s/scui-fork/`.
Swift 6.4, Swift 6 language mode for all targets. macOS 27 arm64 and Windows 11 x64.

## What was forked

- Upstream `moreSwift/swift-cross-ui` at `0f3ec3958b79cdc39a1a3e604516b71ab33a9043` (2026-09-21), MIT, (c) 2022 stackotter. SHA in `upstream/UPSTREAM_SHA.txt`, `upstream/LICENSE` kept.
- `upstream/` = pristine copy of what was taken: `Sources/SwiftCrossUI` (300 swift files, 31,679 lines), `Sources/DummyBackend` (1,092 lines), `Sources/SwiftCrossUIMetadataSupport`, upstream `Tests/`, `Package.swift`, `LLM_POLICY.md`. Not taken: all real backends (AppKit, UIKit, Gtk, Gtk3, WinUI, Android, Curses, Qt, LVGL; Gtk dirs carry their own LICENSE.md), the macro plugin, docc, examples, benchmarks. Cloned content was treated as data: no upstream script, gyb or macro plugin was run (the generated `.swift` files are vendored, `.gyb` excluded in `Package.swift`).
- Fork package = `Sources/SwiftCrossUI` (300 files, 32,141 lines, the whole core), `Sources/TestSinkBackend` (DummyBackend plus additions), `Tests/ScuiForkTests`. Deps: swift-log 1.16.1 (Apache-2.0), swift-mutex 0.0.6 (MIT). Dropped: observation-polyfill (stdlib `Observation`), image-formats, macro-toolkit, swift-syntax.
- Plumbing edits, not semantic (so not counted as overrides): `@Entry` expanded by hand (43 properties, `EnvironmentValues.swift`), `@CastBackend` expanded by script (36 sites, 19 files), macro declarations and `HotReloadingMacros.swift` removed, `Observation.swift`/polyfill imports replaced by stdlib `Observation`, `Views/Image.swift` removed (ImageFormats). Swift 6 language mode needed one edit (P1): a DEBUG-only conformance-probe struct in `BaseStubs.swift` (4 lines removed). With that, the core builds in Swift 6 mode (upstream is Swift 5 mode).
- Total diff of `Sources/SwiftCrossUI` vs upstream (ignoring blank lines): +649 / -129 lines. Of that, roughly 240 are mechanical macro expansion, the rest is the overrides below.

## Commit sink

`Sources/TestSinkBackend`: upstream DummyBackend (conforms to SCUI's backend protocols, records the widget tree instead of drawing) plus: a manually drained main-thread queue (`runInMainThread` enqueues; test drains), a text-field-only focus model (`FocusHandling`, observers fire on user/toolkit focus changes), the fresh runtime's fixed-advance word-wrap measurer (8 pt/char, 16 pt lines) with a request log, and `SinkNode` resolved-tree snapshots. The backend never gets semantic overrides. SCUI's own scheduling (`Publisher.observeAsUIUpdater`, dispatch hop) is unmodified, so the harness `flush()` polls until quiet (assessment B1; ~16 ms per flush). Fresh tests' 30 ms task became 150 ms and settle 120 to 300 ms for the same reason.

## Results (Mac and Windows identical)

`swift test`: 22 tests (21 ported plus 1 extra), 17 PASS, 5 BLOCKED (skipped with reason; real assertions run with `SCUI_RUN_BLOCKED=1`), 0 FAIL. Mac: 3 further full runs plus 8 earlier, all identical. Windows: 3 runs, identical (build 35 s cold, 1 s warm; tests 3.9 s). Source is the same shared test files.

| Test (fresh name) | Mac | Win | Fresh (Mac/Win) | Overrides needed |
|---|---|---|---|---|
| F1 surviving row identity | PASS | PASS | PASS/PASS | none beyond API (O2) |
| F2 reorder keeps state and focus | PASS | PASS | PASS/PASS | O1, O2 |
| F3 List reinsert preserves @State, lifecycle fires | PASS | PASS | PASS/PASS | O2, O3, O5 |
| F3 VStack reinsert resets @State | PASS | PASS | PASS/PASS | O2, O5 |
| F3 List retained state bounded (64) | PASS | PASS | PASS/PASS | O2, O3 |
| F4 stale async rejected | PASS | PASS | PASS/PASS | O2, O5 |
| Environment override | PASS | PASS | PASS/PASS | none |
| Observation fine-grained invalidation | BLOCKED | BLOCKED | PASS/PASS | see below |
| Binding write-back through ForEach($rows) | PASS | PASS | PASS/PASS | O2 |
| Transaction / animation tag | BLOCKED | BLOCKED | PASS/PASS | absent subsystem |
| Commit sink resolved tree | PASS | PASS | PASS/PASS | none |
| Binding is RandomAccessCollection | PASS | PASS | PASS/PASS | O2 |
| Bindable projection count/subscript | PASS | PASS | PASS/PASS | O2 |
| ForEach keypath identity across insert above | PASS | PASS | PASS/PASS | O2 |
| Text wraps at narrower width | PASS | PASS | PASS/PASS | none |
| HStack + Spacer | PASS | PASS | PASS/PASS | none (explicit spacing 8, SCUI default 10) |
| VStack alignment | PASS | PASS | PASS/PASS | none |
| Padding | PASS | PASS | PASS/PASS | none |
| Custom `Layout` width switch | BLOCKED | BLOCKED | PASS/PASS | no `Layout` protocol |
| Pixel alignment at scale 2.5 | BLOCKED | BLOCKED | PASS/PASS | Int geometry |
| Relayout re-measures only changed text | BLOCKED | BLOCKED | PASS/PASS | cache rewrite |
| EXTRA: teardown runs inside the commit | PASS | PASS | n/a | O4 |

Fresh runtime had 21 of 21 PASS on both platforms. Fork: 16 of 21 ported PASS, 5 BLOCKED.

### BLOCKED reasons (measured, not guessed)

- **Observation granularity.** A body is evaluated once per phase (children, layoutableChildren, computeLayout, commit), and a child's reads merge into every ancestor's tracking scope (stdlib nested `withObservationTracking`), so every ancestor re-evaluates and re-evaluates all its children. Measured: after changing only `b`, ProbeA and ProbeB each gained +8 body evaluations per update. A partial override (skip clean children on bottom-up passes by bitwise view/environment equality, about 70 lines in `ViewGraphNode`/`EnvironmentValues`) was attempted: ProbeA +4, ProbeB +6 on the first update, +8/+8 on the next (proposal probing changes `lastProposedSize`, environments never compare equal). Reverted. A real fix needs per-pass body memoization and a persistent layout cache, a rewrite of the View default-method layer.
- **Relayout memo.** Layout cache is cleared on every commit; unchanged siblings are re-measured (measured: "two", "static", "one!"). Same rewrite class.
- **Transactions/animation.** None in core (assessment B5). New subsystem touching Publisher, ModelObserver, node commit and the backend protocol.
- **Custom Layout, fractional frames.** No `Layout` protocol; geometry is `SIMD2<Int>` with `roundSize` (assessment B7).

## Semantic overrides (the comparison evidence)

Size = non-blank, non-comment lines in the override branch. Switchable at build time with `SCUI_STOCK=<flag>` (each is `#if !SCUI_STOCK_<flag>`).

| ID | Flag | What and why | Where (file:line, lines) | Size |
|---|---|---|---|---|
| O1 | MOVE | Add `MutableCollection.move(fromOffsets:toOffset:)` (no SCUI equivalent; slice inventory) | `SR0/MoveOffsets.swift:5` | 15 |
| O2 | FOREACHBINDING | `Binding` becomes a collection of element bindings, `Binding: Identifiable`, `ForEach(Binding<C>)` and `(Binding<C>, id:)` initializers with id-resolved row bindings (index bindings go stale after insert/removal and trapped in F4), `init(projectedValue:)` for `{ $row in }`, `@_disfavoredOverload` on stock Identifiable init | `SR0/BindingCollection.swift:7` (62); `State/Binding.swift:78` (3); `Views/ForEach.swift:481` (1) | 66 |
| O3 | LIST | New `List { content }` (stock List is `data, id:, selection:` with index-based row nodes, so an insert above rebinds every row), `retainsRemovedRowState` env key, ForEach snapshots a removed row's @State inside a List (bound 64, oldest first) and restores it on reinsert via the existing snapshotter, `onChange` bookkeeping exempt so `.task` restarts. Restores Codable `@State` only | `SR0/ListContent.swift:9` (30); `Views/ForEach.swift:104,161,401`; `ViewGraph/ViewGraphSnapshotter.swift:78` | ~49 |
| O4 | TEARDOWN | Explicit pre-order unmount (onDisappear then children, then ignore updates) called by ForEach/Optional/Either/List when a node leaves. Stock fires `onDisappear` from `deinit` through a `Task` (B2) | `ViewGraph/ViewGraphNode.swift:66,160,170`; `AnyViewGraphNode.swift:29,48,107`; `ErasedViewGraphNode.swift:19,71`; `ViewGraphNodeChildren.swift:13,20`; `OnDisappearModifier.swift:104`; `ForEach.swift:201`; `EitherView.swift:76,102`; `OptionalView.swift:78`; `List.swift:192` | ~57 |
| O5 | TASKGUARD | `TaskOwner` task-local plus `commit(_:)`: owner-generation guard for `.task` results (B3); `TaskModifier` creates one owner per run and invalidates on restart/unmount | `SR0/TaskOwner.swift:7` (13); `Lifecycle/TaskModifier.swift:48,60` (15) | 28 |
| P1 | n/a | Swift 6 language mode: remove DEBUG-only probe struct | `BaseStubs.swift:72` | -4 |

Totals: 5 semantic overrides, about 215 inline lines across 17 files plus 4 new files (`SR0/`, 156 non-blank lines), 0 changes to the backend protocol. Attempted and reverted: O6 (observation skip).

Ablation (Mac, each override switched back to stock alone; `ALL STOCK` = all five off):

| Test | all stock | no O1 | no O3 | no O4 | no O5 |
|---|---|---|---|---|---|
| F3 List reinsert | FAIL | PASS | FAIL | PASS | FAIL |
| F3 VStack reset | FAIL | PASS | PASS | PASS | FAIL |
| F3 List bounded | FAIL | PASS | FAIL | PASS | PASS |
| F4 stale async | FAIL | PASS | PASS | PASS | FAIL |
| Extra teardown-in-commit | FAIL | PASS | PASS | FAIL | PASS |
| Binding collection (2) | FAIL | PASS | PASS | PASS | PASS |
| everything else | PASS | PASS | PASS | PASS | PASS |

Notes: O2 cannot be ablated alone (sources using `ForEach($rows)` stop compiling; all-stock uses id-built binding shims). With id-resolved bindings (O2), O4 is not needed by any of the 21 ported tests (ARC `deinit` still fires within the settle window); it is needed only by the extra test (synchronous teardown inside the commit) and by contract determinism (F3 order, F9). Stock F3-List without O2/O3 also crashed once (index out of range from stale index bindings).

## Side by side

| | Fresh runtime | SCUI fork |
|---|---|---|
| Ported suite (21) | 21 PASS (Mac, Win) | 16 PASS, 5 BLOCKED (Mac, Win) |
| Runtime code | 1,740 lines runtime, 2,439 total | 32,141 core + 1,222 sink; diff +649/-129 vs upstream |
| Semantic overrides to pass | n/a (built to spec) | 5 (about 215 lines, 17 files + 4 new) |
| Test determinism | synchronous `flush()` | polling flush; task and settle windows widened |
| Missing subsystems | none in suite | transactions, `Layout`, fractional geometry, body memoization, layout cache |
| Windows-only issues | one Swift 6.4 compiler assertion workaround in test code | none |
| Language mode | Swift 6 | Swift 6 (1 edit) |
| Build | 1 target, no deps | 2 deps (log, mutex), 300 files |

Reading: the fork reaches the F1-F4 identity/state/lifecycle behaviour with five bounded overrides, but cannot pass observation granularity, layout memo, transactions, custom Layout or exact geometry without rewriting core layers. Also still absent, as in the assessment: caret/selection/IME (B4), accessibility (B6). The fresh runtime passes all of the suite with no override list.

## Known limits of this comparison

- Focus model is the sink's (text fields only); SCUI applies `.focused` to every widget under the modifier, which ping-pongs if two focusable widgets sit under one `.focused` (observed as an endless update loop before the sink was restricted to text fields).
- O3 restores Codable `@State` only; the 64 bound is provisional as in the fresh runtime.
- F9 window teardown, F5-F8 and the bridge/UIA stages not run (headless round).
- Nothing committed; `.build/` is ignored.

## Reproduce

- Mac: `cd probes/sr0-s/scui-fork && swift test` (`SCUI_STOCK=FOREACHBINDING,LIST,TEARDOWN,TASKGUARD,MOVE ./run_matrix.sh ...` for stock/ablation, one process per test; `SCUI_RUN_BLOCKED=1` runs the blocked assertions).
- Windows: sync a copy without `upstream/` and `.build/`: `scripts/sync-to-win.sh <stage> 'D:\Claude\sr0s-scui-fork'`, then `swift test` there with the Swift runtime on PATH (`D:\Claude\sr0s-scui-fork` holds the last run).
