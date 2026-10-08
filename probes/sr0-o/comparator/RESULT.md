# SR0-O comparator: trace schema, normalizer, comparator skeleton

Host: Mac mini, macOS 27.0.1 (26A434), arm64, Swift 6.4 (swiftlang-6.4.0.34.1), Swift 6 language mode, Foundation only.
Scope: `probes/sr0-o/comparator/` only. No commits, no branches. Fixture copies are under `Tests/TraceKitTests/Fixtures/` (copied from `probes/sr0-o/ax-routes/out/`).

## Schema v0 (`Sources/TraceKit/Schema.swift`)

- `Trace`: `schemaVersion` ("sr0-o.trace/v0"), `fixtureId`, `sourceHash`, `platform` (os, osBuild, arch, toolchain), `steps`, `observations`, `declaredOrder`.
- `TraceStep`: `id`, `logicalAction`, `nativeMapping`, `timestamp` (recorded, never compared).
- `Observation` per step: `model` (row key `row/<uuid>` to text), `focusedNodeId`, `selection` (UTF-16 location/length), `lifecycle` (appear, disappear, taskStart, taskCancel, taskComplete per row), `effects` (ordered), `axNodes` (nil = not captured at that step).
- `CanonicalNode`: `id`, `role`, `label`, `value`, `actions` (sorted), `parent`, `order`. Frames are deliberately absent.
- `declaredOrder`: edges `kind:node` that must keep their order in any candidate where both events occur. All other lifecycle events may permute.

## Normalizer (`Sources/TraceKit/Normalizer.swift`)

- Mac: AXOutline to list; AXRow with subrole AXOutlineRow to list-item; AXButton, AXTextField, AXStaticText, AXWindow mapped. Containers AXCell, AXColumn, AXScrollArea, AXHostingView, AXGroup are stripped; their children take the nearest kept ancestor's slots. Button label comes from AXDescription (the recorder's `label` key). Other roles keep their raw name, so unlisted containers show up as diffs.
- Actions: AXPress to activate, AXConfirm to confirm, AXShowMenu to show-menu, AXRaise to raise; others keep raw names.
- Stable ids: AXIdentifier when unique in the tree; `identifier~parent#order` when duplicated; `anon:parent#order` when absent.
- Windows UIA stub: Edit to text-field, Button to button, List to list, ListItem to list-item, Window to window, Text to static-text; Pane, Group, Custom stripped. Patterns InvokePattern to activate, ValuePattern to set-value. Tested on the Mac with an inline JSON shape; no live UIA dump yet.

## Comparator and repeatability (`Comparator.swift`, `Repeatability.swift`)

- Exact comparison of fixture id, source hash, steps (id, logical action, native mapping), model per row, focus, selection, effects (ordered), lifecycle counts per event key, and AX nodes (presence, role, label, value, actions, parent, order).
- Lifecycle order: multiset equality, plus declared-order edges. Permutations of undeclared events pass.
- Timestamps and platform tuple never fail (platform difference is a note).
- Adaptations: `{field, nodeId?, mapping?, allowAnyValue?, reason}`. Entries with an empty reason are ignored.
- Diffs carry fixture, step, path (`leaf[node]`), expected, actual.
- Repeatability: run 1 is the reference; reports all-agree, disagreeing paths, and flagged runs (1-based).

## Commands

```
cd probes/sr0-o/comparator
swift build
swift test
SR0O_EMIT_DIR=<dir> swift test --filter emit_when      # writes trace JSON for the CLI check
.build/debug/sr0o-trace compare <accepted.json> <candidate.json> [--adapt adapt.json]   # exit 0 pass, 1 fail, 2 error
.build/debug/sr0o-trace repeat <run1.json> <run2.json> ...
```

## Test results (`swift test`, trimmed)

```
Test run with 16 tests in 5 suites passed.
```

Per-test lines in the run (trimmed; "after N seconds" removed):

```
✔ accepted_F1_matches_probe_shape            (Accepted baselines)
✔ identical_candidate_passes
✔ permuted_unordered_lifecycle_passes
✔ timestamps_and_platform_build_do_not_fail
✔ a_wrong_row_identity_fails                 (Injected faults)
✔ b_stale_task_commit_fails
✔ b2_declared_order_violation_fails
✔ c_missing_activate_action_fails
✔ d_extra_container_fails
✔ e_label_change_fails
✔ e2_label_change_passes_only_with_reasoned_adaptation
✔ unlisted_stripped_name_is_not_silently_removed
✔ twenty_identical_runs_agree                (Repeatability)
✔ one_variant_run_is_flagged
✔ maps_control_types_and_strips_named_containers  (UIA stub)
✔ emit_when_requested                        (trace emission for CLI)
```

Fault diffs, verbatim from the run (trimmed):

```
FAULT a diffs:
  after_type_d model[row/...0005]: expected Row 5abcd, got Row 5abc
  after_type_d model[row/...0006]: expected Row 6, got Row 6d
  after_type_d focusedNodeId: expected row/...0005/field, got row/...0006/field
  after_type_d selection: expected location=9 length=0, got location=6 length=0
FAULT b diffs:
  release_completion model[row/...0005]: expected <absent>, got async-42
  release_completion effects: expected <none>, got commit-task-result row/...0005 async-42
  release_completion lifecycle.count[taskComplete:row/...0005]: expected 0, got 1
FAULT c diffs:
  initial axNodes.actions[toolbar/insert]: expected ...,activate,show-menu, got ...,show-menu
FAULT d: 32 diffs; the wrapper shows as: axNodes.role[anon:main#0] actual=AXSplitGroup
FAULT e: initial axNodes.label[toolbar/insert]: expected "Insert above", got "Insert below"  (only diff)
REPEAT variant: 20 runs, flaggedRuns [14], disagreeingPaths ["initial axNodes.label[toolbar/insert]"]
```

## Fault verdicts

| Fault | Injection | Verdict |
|---|---|---|
| (a) wrong row identity | After "d", focus on row 6, text lands in row 6, selection 6 | PASS: rejected; 4 precise diffs (model rows 5 and 6, focusedNodeId, selection) |
| (b) stale task commit | Completion after cancel writes `async-42` to row 5 with an effect and taskComplete | PASS: rejected; 3 diffs (model, effects, lifecycle count) |
| (b2) declared-order violation | disappear and taskCancel swapped in the same step | PASS: rejected; exactly one `lifecycle.order` diff |
| (c) missing accessibility action | AXPress removed from toolbar/insert | PASS: rejected; exactly one diff (actions lose `activate`) |
| (d) extra container | AXSplitGroup wraps AXOutline (not in the strip list) | PASS: rejected; the wrapper appears as a role diff at `anon:main#0`, plus cascaded parent/id diffs (32 total) |
| (e) label change | toolbar/insert AXDescription "Insert above" to "Insert below" | PASS: rejected; exactly one diff. Passes only with a reasoned adaptation (e2) |

Positive controls: identical candidate PASS; permuted undeclared lifecycle PASS; repeatability of 20 identical traces PASS (all agree); the one variant in 20 is flagged (run 14).

## CLI check (`sr0o-trace`, real files)

```
compare accepted-f1 vs candidate-identical         -> exit 0
compare accepted-f1 vs fault-a-row-identity        -> exit 1, diff: focusedNodeId only (see note)
compare accepted-f1 vs fault-c-missing-press       -> exit 1
compare accepted-f1 vs fault-e-label               -> exit 1
compare accepted-f4 vs fault-b-stale-commit        -> exit 1
compare accepted-f1 vs fault-e-label --adapt ...   -> exit 0
repeat accepted-f1 candidate-identical fault-e     -> exit 1
```

Note: the emitted `fault-a` file changes only focusedNodeId; the unit test fault (a) also changes text, selection and row 5 and 6 text. Both are rejected.

## Windows build

Full directory sync exceeded the sync limit: archive with fixtures 27,308 chars; without fixtures still 27,308 chars (limit 24,000). I synced a library-only copy (`Sources/TraceKit` and `Sources/TraceTool` plus a Windows manifest without the Mac-only test target) to `D:\Claude\sr0o-comparator`. Staging was in scratch, and the probe directory was not modified. Archive 13,656 chars.

```
swift --version: Swift version 6.4 (swift-6.4-RELEASE), Target: x86_64-unknown-windows-msvc
swift build: [43 / 43] TraceKit-product; Build complete! (27.68 secs); exit=0
```

Remaining warnings are from the Windows SDK's WinSDK module (`wchar_t`), not from this code.

## Findings and open items

1. Duplicate AXIdentifiers are real: AppKit menu items reuse identifiers such as `_recentItemRequested:` (21 times). The first normalizer produced 30 duplicate ids and failed the identical test. Fixed by qualifying duplicated identifiers with parent and order. Same rule in the UIA stub.
2. The toolbar/insert action list in the probe includes raw AppKit custom actions (`Name:Remove from toolbar\nTarget:0x0\nSelector:(null)`). The normalizer keeps them unchanged, so they appear in the accepted baseline. SR0-C must decide whether custom actions are platform-generated and stripped, or kept as observed.
3. The accepted F1 trace is based on real probe data but only the initial snapshot has AX nodes. The probe logged only row 5 text per step, so other rows use the fixture's initial "Row N" text. F1 declares no lifecycle order constraints because the probe recorded none.
4. F4 is a synthetic baseline (test-authored, `sourceHash` "synthetic:test-authored"). The probe recorded no tasks, so the task-lifecycle checks prove the comparator, not the Mac behavior. SR0-O still needs a recorded F4 trace.
5. Frames and geometry are not in the v0 schema, so F5 layout and paint-hit-test checks are not covered yet.
6. Fix iterations used: 2 (duplicate-identifier normalizer; test expectation corrections). Within the limit of 4.
