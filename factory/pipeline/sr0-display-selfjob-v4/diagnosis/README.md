# Rectangle Count1r2 host diagnosis

Archived failed host:
`factory/native/windows/pilot-rectangle-fixed-root-v2/actual-failed-count1-r1/native/native-01/`

Evidence binds failed & prior working hosts to same host source (`sourceHash` `5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d`), executable (`62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66`), renderer (`e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`), Bridge Loader (`10144b99141508043ca2ab86d72ac444e89d770193753115cc68e683aaa6f768`), Bridge (`d0768273e76a0ec3a6b71e8e8ac6a0a359be7ab6051e1e77ac40d4670c7118b8`), & runtime tree (`c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`).

Failed stderr contains only `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2) -> 1`. That marker is emitted inside renderer `view::run` at `render/swiftright-render/src/view.rs:1612`, after `Bridge.load` returns, callbacks are installed, & `bridge.run` begins. Therefore archived evidence does not support a `Bridge.load` deadlock. It points to GPUI/Application startup after DPI setup, before `loop_ready`/window metrics. Missing `FACTORY_BACKGROUND_GUARD` is not reliable because stdout capture was incomplete; stderr marker proves renderer entry.

Coordinator timing is also inconsistent: `control/coordinator.json` records `native task deadline` at `22:02:39.989Z`, while retained host starts at `22:03:15.617Z` (+35.6 s). `control/task-result.json` still says scheduler task running. Treat this as late/stale task dispatch evidence during diagnosis; bind each host launch to current scheduler run ID before attributing startup failure to Bridge.

Use `bridge-load-trace-v1.swift` in fresh diagnostic host. Emit trace to stderr before/after `Bridge.load`, before/after hook, before/after `bridge.run`; optional loader probe separates `LoadLibrary`, bootstrap query, & API-table query. Keep renderer, Bridge, runtime, hook, desktop, & lock sources unchanged.

## Phase attribution

This failure has two independent clocks. Coordinator receipt `control/coordinator.json` reports `native task deadline` at `2026-10-11T22:02:39.9895Z`, with scheduler still running. Retained renderer starts at `2026-10-11T22:03:15.6179Z`, 35.6 seconds later, so that receipt cannot be used as renderer-start evidence. Bind `task-start.runID`, scheduler task instance, host PID/path/start time, & native directory before assigning either deadline.

Native host evidence begins at the renderer DPI marker (`view.rs:1612`), after `Bridge.load`, callback installation, & `bridge.run` entry. No `loop_ready`, `onReady`, or window metric marker appears before capture's native window deadline. This proves renderer entry but does not distinguish GPUI startup before HWND creation from an HWND not exposed through `MainWindowHandle`. `capture-lease` stdout is only 89 bytes; absent stdout markers are loss of evidence, not proof hook installation failed.

`WorkloadStartupGuard.swift` installs a same-thread `WH_CBT` hook that vetoes `HCBT_ACTIVATE` & `HCBT_SETFOCUS`; it does not create or query HWNDs. Failed rectangle host contains equivalent activation veto code. Keep guard A/B as an observed input, never as an inference from missing stdout. Factory-only trace must write `before-load`, `after-load`, `hook-installed`, `before-run`, `loop-ready`, `onReady`, `first-window-metrics`, `window-closed`, & `after-run` to stderr with one scalar line per phase.

`Bridge.load` itself performs only `LoadLibraryW`, `GetProcAddress`, bootstrap query, ABI validation, & API-table query (`factory/native/windows/padding-window-diagnosis-build-v1/dependencies/SwiftRightBridge/Sources/SwiftRightBridge/Loader.swift:19-61`). It has no JSON or `DateTime` conversion. Bridge event buffering is lazy and unused by failed host's callback path. Therefore recursive JSON conversion is an inspector/coordinator risk, not an established renderer cause.

## Unsafe active inspectors

Historical inspectors must not run beside live work. Exact hazards:

* `factory/pipeline/sr0-display-selfjob-root-v4/inspect-base-r2.ps1:4-6` parses whole `build.json`, then serializes `$b` at `-Depth 16`.
* `factory/native/windows/pilot-rectangle-fixed-root-v2/inspect-count1-r1.ps1:3-5` parses each receipt, stores nested values, then serializes all values at `-Depth 20`.
* `factory/native/windows/pilot-rectangle-fixed-root-v2/inspect-count1-v3-terminal-r2.ps1:3-7` reads receipt text, process/CIM rows, children, & file inventory, then recursively serializes at `-Depth 22`.
* `factory/native/windows/pilot-rectangle-fixed-root-v2/inspect-count1-deadline-r2.ps1:2-7` parses task receipts & recursively serializes them at `-Depth 20`.

`ConvertFrom-Json` materializes complete object graphs; `ConvertTo-Json -Depth` walks them again. `DateTime` values in parsed graphs amplify this path, but no evidence shows them in native host startup. Use `inspect-flat-receipts-v1.ps1` for explicit receipt paths: each regular non-reparse file is capped at 2 MiB, aggregate at 8 MiB, only fixed scalar keys are regex-extracted, hashes & byte counts are retained, and output is manually bounded JSON. It requires `sr0-root-transport-job-v1` before launch; root must run it inside existing 256 MiB transport job.

Root execution order for one fresh diagnostic: admit transport job; run flat inspector on exact archived receipts; stage host with unchanged source/runtime/renderer hashes; launch one host in same session; retain host handle; collect stderr phase lines; classify coordinator & native clocks separately; then perform existing cleanup proof. No renderer, Bridge, StartupGuard, or receipt source is edited by this packet.

For archived-only inspection, pass explicit files from `factory/native/windows/pilot-rectangle-fixed-root-v2/actual-failed-count1-r1/control/` (`task-start.json`, `task-result.json`, `coordinator.json`, `deadline-reconcile.json`) and `native/native-01/` (`owned-process.json`, `lifecycle-timing.json`, `capture-outcome.json`, `host.stdout.txt`, `host.stderr.txt`) to `inspect-flat-receipts-v1.ps1`; keep output in pre-existing `.work` output root. Run that PowerShell child only after root transport Job Object admission, with helper/script pins recorded in transport receipt.
