# SR0 close plan

9 October 2026. Goal: close SR0 (all stages D, C, O, B, S, P, A pass with receipts). SR1 work stays paused until this plan is done unless Adrian says otherwise.

## Constraints that shape the parallelism

- **Dell desktop is one lane.** Only one windowed run at a time (matrix, smoke, Sandbox checks). SSH-only work (builds, signing, verification) runs alongside it.
- **Adrian's Mac has no windowed runs** unless he says it is free. Headless builds, signing and notarization are fine.
- **Release builds need a clean, committed tree** (`right-release` source gate). Nothing may be left uncommitted when a sealed build starts.
- **RightKit publication is RightKit Mac's.** Pre-publication builds use the local RightKit tree, labelled as such; no upload.
- **No restart of the Dell while a desktop run is active.**

## Lanes

| Lane | Host | Runs in parallel with | Steps |
|---|---|---|---|
| L1 Dell desktop | Dell interactive session | L2, L3, L4, L5 | 1. Finish 20-run matrix (running, ~150/300). 2. Adrian restarts Dell (Sandbox). 3. Clean-machine Windows checks in Windows Sandbox (install, offline launch, upgrade, rollback, corrupt update, interrupted update, uninstall keeps data, virtualization, dependency closure). |
| L2 Windows builds (SSH) | Dell, no desktop | L1 step 1, L3 | 1. After matrix commit: sealed MSIX build + Authenticode sign. 2. Verify: `signtool verify /pa` (package + inner exe/DLLs), Publisher == signer subject, unpack matches 18-DLL inventory, `.appinstaller` well-formed. |
| L3 Mac builds (headless) | Mac | L1, L2 | 1. After matrix commit: sealed `.app` + DMG, sign, notarize, staple. 2. Verify: `codesign --verify --deep --strict`, `spctl --assess`, `stapler validate`. |
| L4 Freeze documents | Mac, text only | all | 1. Apply matrix-20b result to the contract proposal. 2. After L6: mark slice contract v1.0 and bridge ABI 0.5 FROZEN with commit + renderer sha256. |
| L5 RightKit publication | RightKit Mac | all | Publish `@rightkit/release` 0.2.138 (handoff sent); then pin SliceApp to it and rebuild L2/L3 once (same checks). |
| L6 Signed Mac recorder | Mac, short windowed run | needs Adrian | 1. Adrian grants Accessibility to `probes/sr0-o/f1-cross/out/signed/F1MacRecord.app`. 2. When Adrian says the Mac is free (~5 min): re-record Mac F1 with the signed recorder, rerun cross-platform compare (expect 0 diffs). |
| L7 Clean Mac checks | clean macOS user or VM | after L3 | Install via DMG, offline first launch (decides whether DMG staple alone suffices), upgrade, corrupt-binary rejection, interrupted copy, uninstall keeps data. Adrian provides the clean environment and launches the app. |
| L8 Automation | Mac + Dell | after L1 step 3, L2, L3 | `qualification/run.py` end to end: mac-oracle (all 16 accepted configs), win-replay, compare, smoke, packaged checks; every stage passes with artifact ids recorded. |

## Dependency graph

```text
L1.1 matrix ──► commit ──┬─► L2 MSIX build+verify ──┐
                         ├─► L3 DMG build+verify ───┼─► L7 clean Mac ──┐
                         └─► Adrian restarts Dell ──► L1.3 Sandbox ─────┼─► L8 automation ─► SR0 CLOSED
L6 grant ─► L6 re-record + compare ─► L4 freeze ─────────────────────────┘
L5 publish 0.2.138 ─► pin + rebuild L2/L3 (re-verify) ───────────────────┘
```

## Critical path (agentic wall clock, estimate)

Matrix finish (~1.5 h) → commit → builds L2/L3 in parallel (~1 h) → Sandbox checks (~1 h) → automation (~0.5 h). L6, L7 and L5 hang on Adrian / RightKit Mac and can land any time before L8.

## What Adrian does

1. Restart the Dell **after** I report the matrix finished.
2. Grant Accessibility to `F1MacRecord.app` (any time).
3. Tell me a ~5-minute window when the Mac is free for the signed re-record.
4. Provide a clean macOS user or VM for L7, and launch the app there when asked.

## Done criteria for SR0

Every row in `docs/sr0-status.md` PASS with receipts; contract v1.0 and ABI 0.5 frozen; signed DMG and MSIX verified and clean-machine checked on both OSes; automation runner green end to end. Windows arm64 recorded as an exclusion (no host).
