# SR0 slice contract (SR0-C)

Status: DRAFT v0.1, 9 October 2026. Freezes when the same-source compile probe passes on both targets and the D-stage observation routes below are confirmed. After freeze, changes need a documented contract revision and a rerun of both seeds (architecture §11).

## 1. Pinned tuple (initial)

| Item | Value |
|---|---|
| Mac oracle of record | Mac mini, macOS 27.0.1 (26A434), arm64, Xcode 27.0, Swift 6.4 |
| Mac deployment floor | macOS 14 (Observation); not traced in SR0 |
| Windows lane | Dell XPS 15, Windows 11 Pro 26300, x64, Swift 6.4.0 (swift-6.4-RELEASE), Rust 1.98.0 via RightKit |
| Windows arm64 / Intel Mac | Out of scope (scope revision 1, `docs/architecture.md` §9) |
| Renderer | gpui 0.2.2 + accesskit 0.25.1 + accesskit_windows 0.35.1, lockfile `probes/sr0-d/render-composition/Cargo.lock` |
| Dispatch | `_dispatch_main_queue_callback_4CF` in Swift 6.4.0 runtime dispatch.dll (ordinal 23) |
| Language mode | Swift 6, strict concurrency |

GPU/driver, fonts, locale, DPI and refresh are recorded per run in fixture metadata.

## 2. Slice inventory

Only these APIs and compositions are in SR0. Everything else is unsupported for SR0 and must fail Windows compilation or be absent.

| Group | APIs |
|---|---|
| Views | `Text`, `Button(_:action:)`, `TextField(_:text:)`, `VStack`, `HStack`, `Spacer`, `List`, `ForEach(_:id:)` over `Binding<[Row]>`, custom `Layout` |
| State | `@State`, `Binding`, `@Bindable`, `@Observable` (stdlib Observation), `@Environment` with one custom `EnvironmentKey`, `@FocusState` with `.focused(_:equals:)` |
| Lifecycle | `.onAppear`, `.onDisappear`, `.task` (cancellation on disappear) |
| Lists | `.onMove`, `MutableCollection.move(fromOffsets:toOffset:)`, deletion via model command, stable `id` per row, `ForEach($items) { $item in }` binding projection |
| Animation | `.animation(_:value:)`, `withAnimation`, reduced motion via environment |
| Entry | SDK root factory; Mac one `Window` scene; Windows synchronous initial-thread entry |

`Layout` subset: `sizeThatFits(proposal:subviews:cache:)` and `placeSubviews(in:proposal:subviews:cache:)`, with `ProposedViewSize` and `Subviews` size queries only. No layout values, priorities, or spacing APIs in SR0.

Negative fixtures: `.onReceive`, `ObservableObject`/`@StateObject`, `NavigationSplitView`, `Timer.publish` each must fail Windows compilation with a diagnostic.

## 3. Fixtures

Each fixture names its source hash, initial state, stable node IDs, stimuli, settlement condition and assertions. Node IDs are model-level row UUIDs plus a fixed control role suffix (`row/<uuid>/field`, `toolbar/insert`).

| ID | Purpose | Stimuli (logical) | Required assertions |
|---|---|---|---|
| F1 surviving-row identity | Edit survives unrelated insert above | Focus row 5, type "abc", fake engine inserts row at index 0, type "d" | Row 5 text "…abcd", focus & caret stay on row 5 identity, `@State` of row 5 unchanged |
| F2 reorder | Identity survives move | Focus row 3, caret mid-text, `onMove` row 3 → index 7 | Same identity focused, caret offset unchanged, accessibility order updated |
| F3 removal/reset | Removed row tears down | Focus row 4, delete row 4, reinsert same UUID; run in `List`, `VStack`+`ForEach` and `LazyVStack` | Mac-recorded teardown order: onDisappear, task cancel. Reinserted `@State` follows the container's recorded Mac outcome: macOS 27 `List` preserves it (0/1/3 s gaps), `VStack` and `LazyVStack` reset it (1/3 s), all deterministic. Windows replays each container separately. |
| F4 stale async | Guarded stale result | Start row task, remove row before fake completion fires | Cancellation delivered; result not committed to any row; cleanup observed |
| F5 width layout | Width-dependent custom Layout | Resize window across wrap threshold during async updates | Containment, no clipping of caret, paint = hit-test = AX bounds |
| F6 interrupted animation | Transaction semantics | Insert row with animation, insert again mid-animation | Interruption recorded, final layout settled, completion order; reduced-motion variant has no intermediate frames |
| F7 IME | Composition on active row | Begin composition, insert row above, commit | Marked text stays on original identity; committed text lands there |
| F8 accessibility | Activation & editing via AX/UIA | AX press insert button; set value on row; move focus | Model state changes, roles/labels/actions per canonical map |
| F9 window teardown | Close with live tasks | Close window with pending tasks & engine callbacks | Tasks cancelled, no commits after close (Mac oracle). Tree release after close is a Windows runtime requirement (architecture §6), not a Mac oracle assertion: AppKit keeps closed `NSWindow`s alive in the fixture host. |

Within one step, sibling lifecycle events from different nodes are unordered unless a fixture declares an order; per-node event order is always significant.

**C9 (proposed, F6 decision): the F6 animation completion pair is unordered.** In F6 the `animation` node's `complete` events for tag A and tag B may occur in either order. Native SwiftUI swaps them in about 4% of runs (100-run Mac sample: 96 A-first, 4 B-first, clustered; `probes/sr0-o/r6/f6/`), so no order is a property of the platform. Only that pair permutes (canonical form: the two completion events keep their slots in the node sequence and are sorted by tag). Everything else stays exact: each tag's `start` precedes its `complete`, each completes exactly once, a missing, duplicated or relocated completion fails, all other events and lifecycle order are unchanged, and the final state must match. Implementation: `probes/sr0-o/fixtures/scripts/normalize-hash.py` (`f6_unordered_completions`); `qualification/run.py canonical_body` must mirror it. Accepted baselines are unchanged. Evidence: `probes/sr0-o/F6-UNORDERED.md`. Each Mac fixture runs 20 times; all normalized assertions must agree before it becomes an oracle. Each Windows seed runs 20 times with all passing.

**C11 (proposed, F6 decision): `onAppear`/`onDisappear` counts for List rows inserted under an animation are unspecified.** On macOS, SwiftUI re-creates every List row that was inserted under an animation when that insertion animation completes, including a row whose animation was never interrupted: rows 200 and 201 of F6 show `appear` twice and `disappear` once on the Mac, the fresh Windows runtime keeps the row views (`appear` once, `disappear` zero; seen with animations on and off, `probes/sr0-o/f1-cross/CROSS-ALL.md`, D3). Only the lifecycle counts of those rows differ; F6 still asserts the interruption record, the completion pair (C9), the final layout and state. Comparison: the four `lifecycle.count` pairs (`appear` 2 to 1 and `disappear` 1 to 0 for the two inserted rows, step `initial`) are a scoped allowance in `probes/sr0-o/f1-cross/cross/F6/adapt-v0.json`; no other count is relaxed, and an injected fault outside the pair must still fail. Mac is the oracle for nothing here: a conforming implementation may report either count.

## 4. Stimuli & native mappings

| Logical action | Mac | Windows |
|---|---|---|
| Copy / Paste / Undo / Redo | Cmd-C / Cmd-V / Cmd-Z / Shift-Cmd-Z | Ctrl-C / Ctrl-V / Ctrl-Z / Ctrl-Y |
| Select all | Cmd-A | Ctrl-A |
| Move focus | Tab / Shift-Tab | Tab / Shift-Tab |
| Activate | Space on focused button; AXPress | Space; UIA Invoke |
| Composition | Japanese IME (Kotoeri) romaji | Microsoft Japanese IME romaji |

Async completions come from an injected fake engine and clock; fixtures release them explicitly. No assertion depends on SwiftUI's private scheduling.

## 5. Observation routes

| Observation | Mac | Windows |
|---|---|---|
| Model state, lifecycle, effects | In-process instrumentation in shared fixture code | Same |
| Accessibility tree, roles, actions, bounds | AX API out of process (signed recorder with AX permission) | UIA out of process (proven: `probes/sr0-d/render-composition`) |
| Focus & caret | AX focused element, `AXSelectedTextRange`, `AXBoundsForRange` | UIA focus, TextPattern selection & `GetBoundingRectangles` (TextPattern not yet proven) |
| Marked text | Bounded input/output assertion only (no public marked-text observation) | Runtime-owned buffer state |
| Visible response | Input event timestamp from the injecting recorder (mach absolute time) to the first frame containing the response, detected by ScreenCaptureKit frame timestamps on a recorder-owned stream (decided 9 Oct 2026; optical capture remains the cross-check if ScreenCaptureKit latency is not calibrated) | SendInput QPC timestamp to PresentMon `msUntilDisplayed`-derived display time of the first present after the event that contains the response (decided 9 Oct 2026; same clock domain, QPC) |

Canonical roles: window, button, text-field, list, list-item, static-text. Platform containers named in the normalizer are stripped; nothing else.

Mac route evidence (`probes/sr0-o/ax-routes`, macOS 27): tree walk, `AXIdentifier`, `AXPress`, `AXFocused`, `AXSelectedTextRange` and `AXBoundsForRange` all work against real SwiftUI; row identity keeps focus across an insert above. Normalizer rules from that run:
- Map `AXOutline` → list, `AXOutlineRow` → list-item; strip `AXCell`, `AXColumn`, `AXScrollArea`, `AXHostingView`, `AXGroup` containers.
- Button label comes from `AXDescription`, not `AXTitle`.
- Keyboard stimuli post to the fixture pid (`CGEvent.postToPid`) unless the driver proves the fixture is frontmost; never type through the global HID tap blind.
- Caret bounds use a one-character range; a zero-length range returns zero width.
- The recorder must hold its own Accessibility grant as a signed binary before O; the probe ran under the terminal's grant.

## 6. Bridge ABI v0 vocabulary (frozen only after SR0-B)

- Bootstrap query: ABI major/minor, architecture, pointer width, function-table sizes into caller-sized buffer.
- Commit transaction: version, window generation, node upserts/removals, geometry in physical pixels, primitive list per node (text run handle, image, path, clip, transform), semantic node per node (role, label, value, actions, text selection), focus target.
- Measurement: synchronous text measure returning size, baselines and retained shaped-run handle; cache key (text, font+version, width, locale, direction, DPI, and text colour while colour is baked into shaped runs — ABI v0 does this).
- Events: input, focus, IME (IMM32 function table), AX action records, display tick; each tagged with window generation, node identity and snapshot version.
- Ownership: opaque generation-tagged handles, explicit release, owner-frees, panics contained.

## 7. Budgets

Copied from architecture §11 decision budgets, including revision 1 (presentation limit = zero missed vblanks + p95 ≤ refresh + 0.1 ms, measured by PresentMon on an unoccluded window); frozen with this contract.

## 8. Open before freeze

- ~~Same-source compile probe~~: PASS on macOS 27 arm64 & Windows x64 with an identical screen file; negative `NavigationSplitView` fixture fails on Windows only (`probes/sr0-c/same-source`).
- ~~TextPattern on Windows edit nodes; Mac AX caret routes for SwiftUI `TextField`~~: met (`probes/sr0-b/text-geometry` run 4, `fcc999d`; `probes/sr0-o/ax-routes`).
- ~~Visible-response endpoint method per OS~~: decided (§5).
