# SR0 tuple12 qualification handoff

Updated 11 October 2026. This is a launch plan; no tuple12 job has run.

## Pinned inputs

- source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- renderer: `C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F`
- RightKit release adopted by source: `@rightkit/release` `0.2.151`
- tuple candidate: `qualification/tuple12-candidate.json`
- last qualified baseline: tuple11; Dell tuple12 root was absent after stage parser failure

Candidate JSON has exactly seven members accepted by `qualification/run.py`. Fill it only from reviewed byte-bound binary or sealed run receipts with `qualification/tuple12-fill.py`; helper records source & artifact SHA-256 joins, rejects unsafe paths, & requires fresh source revalidation for every prepopulated member on later invocations. Null hashes or missing source files intentionally fail launcher validation. Controls are archived in `qualification/tuple12-fill-controls-results.json`.

## Root-owned sequence

1. Transfer archived no-delete stage tools to isolated Dell `.work\sr0-stage-tools`; run parser preflight, read-only audit, then fresh tuple12 stage under unique `.work\sr0-r12`. Preserve any partial tree; never delete Dell data.
2. Verify source commit, renderer hash, toolchain paths, and every stage receipt. Build fixture, smoke, package, workload, and native artifacts only after tuple12 stage passes. Bind each receipt to source commit and renderer hash above.
3. Fill seven tuple pins from receipts. Run `qualification/tuple12-run.sh --confirm-windows-gui` with explicit tuple12 workload/native/package paths. Launcher forces `--runs 20 --win-runs 20`; `--dry-run` is available for plan inspection.
4. Run full 16-config Windows matrix with `RUNS=20` through `qualification/tuple12-windows-matrix.sh`; pass `BASE_DIR`, FreshOnBridge hash, renderer hash, and unique `OUT_DIR`. Existing matrix preflight must pass before any UI job. Root must hold `D:\Claude\desktop.lock`, log first-ready UTC, PID/HWND, `WindowMetrics`, `GetClientRect`, DPI, and verify same-process HWND remains valid through close before releasing lock; current `drive-fixture.ps1` lacks complete startup telemetry, so matrix launch stays held until wrapper/patch supplies it.
5. Run 20 Windows cross recordings per config with `qualification/tuple12-cross20.sh`; set `BIN`, `EXPECT_EXE`, `EXPECT_RENDERER`, and unique output path. Compare against 20 Mac observations per config from approved tuple12 Mac fixture receipts. Cross config keys are `F1`, `F2`, `F3`, `F3-list-1s`, `F3-list-3s`, `F3-vstack-1s`, `F3-vstack-3s`, `F3-lazy-1s`, `F3-lazy-3s`, `F4`, `F5`, `F6`, `F6-reduced`, `F7`, `F8`, `F9` (16 total; matrix uses its `F3:list-0s` spelling).
6. Re-run native R9 & workload R10 receipt analyzers against tuple12 renderer. W08 remains open until upstream repair-helper proof passes on actual installed release; no limitation acceptance. Required W08 artifact set: RightKit helper source/version/hash & install-registration receipt; clean package old/new hashes; genuine cancellation receipt showing `Modified, NeedsRemediation`; helper command/exit/state-transition receipt; relaunch receipt; data-integrity/legacy-path receipt; final package status & signed-source receipt. Manual Settings Repair or same-version redeploy receipts cannot substitute for upstream helper proof.
7. Freeze stays held until stage, renderer/source binding, matrix, native/workload, package, W08, and 20-per-side comparison receipts all pass. Narrator audio remains human-listen follow-up after automated qualification.

## Safe command shapes

```sh
# plan only; no Dell effect
qualification/tuple12-run.sh --dry-run --stages mac-oracle win-replay compare workload native smoke package

# Windows matrix, root supplies reviewed values
BASE_DIR='D:\Claude\swiftright\.work\sr0-r12\src' \
EXPECT_EXE_SHA256='<tuple12 FreshOnBridge sha256>' \
EXPECT_DLL_SHA256='C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F' \
OUT_DIR='qualification/out/tuple12-windows-20' \
qualification/tuple12-windows-matrix.sh

# cross recordings, root holds D:\Claude\desktop.lock
BIN='D:\Claude\swiftright\.work\sr0-r12\src\scratch\out\Products\Release-windows-x86_64' \
EXPECT_EXE='<tuple12 FreshOnBridge sha256>' \
EXPECT_RENDERER='c62b554b4b2545b8be2429c2530e17b8c8b78df97e67172b627e8cd18a5fe68f' \
qualification/tuple12-cross20.sh qualification/out/tuple12-cross-20
```

These wrappers are prepared only. Root serializes remote Windows, native, GUI, signing, and desktop-lock execution.

## Closure split

Computable close jobs: tuple12 stage/audit, source/header/hash binding, 16-config matrix, native R9, workload R10, package receipts, W08 helper proof, 20 Mac + 20 Windows cross traces/config, comparator controls, and manifest/freeze receipts. Human-only follow-up: listen to retained Narrator speech recordings on qualified tuple12 package, record listener/date/verdict, then attach receipt; it cannot turn failed automated gates green.
