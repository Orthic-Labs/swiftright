# SR0 close plan (v2)

9 October 2026, revised after an adversarial Astra review of v1. Goal: close SR0 with receipts that cannot be false-green. SR1 work stays paused until SR0 closes unless Adrian says otherwise.

**Status 11 October 2026 (HEAD `61be5f94`): SR0 is open; lane states are in "Lane status" at the end of this file. The plan text between is unchanged and is the plan, not the state; state cells in the "Lanes" table below were last edited on tuple 08 and are superseded by "Lane status".** Current state: `docs/sr0-status.md`; final tuple: tuple 11, `docs/sr0-snapshot.md` section 2e (sections 2d and 2c are superseded).

## Decisions recorded

- **Scope:** Windows x64 + macOS arm64 only (architecture §9 "Execution hosts", scope revision 1, approved by Adrian). No arm64 Windows, no Intel Mac.
- **Mac test session:** windowed Mac runs (recorder, fixtures) use a separate macOS user over Remote Desktop with its own virtual display, never Adrian's screen. Adrian creates the account; agents never create OS accounts.
- **SR0 qualification snapshot:** bridge ABI **0.6** (append-only superset of 0.5). All SR0 receipts must bind to one tuple: runtime commit, bridge/header commit, renderer DLL sha256, app/fixture binary sha256. Existing 0.5 evidence stays as history; final native evidence is rerun on the 0.6 tuple.
- **Seeds:** the SwiftCrossUI fork is recorded as *early-disqualified* (5 core semantic areas blocked headless, retry cap spent), not as a completed same-backend comparison.

## Review findings that change the work (all verified or accepted)

| # | Finding | Fix |
|---|---|---|
| F1 | Windows package would omit the dynamically loaded renderer DLL; inventory check would still pass | Stage the checksum-pinned renderer + its closure explicitly; verify installed app loads it with developer PATH and `SWIFTRIGHT_RENDER_DLL` unset |
| F2 | Freeze names ABI 0.5, code is 0.6 | Single 0.6 snapshot manifest (above) |
| F3 | Automation runner can report false green (skips smoke, no package stage, passes on skips, compares before replay, Windows PASS without artifact ids) | Fix runner; required stages fail on skip/missing evidence |
| F4 | Canonical digest sorts all events in a step, hiding per-node order faults (contract §3 says per-node order counts) | Per-node-ordered canonical form; fault-injection test; recompute accepted baselines and 20-run results from saved JSONL |
| F5 | Windows matrix lacks F3 3 s variants; real IME and screen reader untested | Extend matrix; real IME + Narrator/NVDA lane |
| F6 | Recovery checks don't exercise real interruption; data-path checks miss MSIX virtualization | Real interruption at install/copy/swap boundaries; old+new packages; legacy and fresh data inspected at physical paths |
| F7 | §11 full workload (200 rows, warm-up, 3×60 s, all thresholds) never run on the selected runtime | Full workload lane on both OSes, quiet hosts |
| F8 | App Installer route not qualified while URLs are `.invalid` | Local-hosted (file or loopback https) App Installer feed for the update checks, or record as untested |
| F9 | Stale status/freeze text | Reconcile before freezing |
| F10 | Canonical v2 (per-node order) exposed F6 variance: interrupted-animation completion order A/B swapped in 1/20 Mac runs | F6 NOT qualified; 100-run sample in the Mac test user (R6) decides genuine SwiftUI variance (then a contract revision) vs fixture defect. No permitted-ordering declaration before that evidence |

## Lanes

| Lane | Starts | Host / resource | Work | Done when |
|---|---|---|---|---|
| R0 Evidence & snapshot | now | Mac, text | Reconcile status/freeze docs; write the 0.6 snapshot manifest; seed disposition; retry ledger | One manifest names every artifact hash; docs agree |
| R1 Dell desktop | (a) DONE: smoke 40/40, timeout mode 41/41 on tuple 08; text geometry 20/20 and real modal paths 20/20 (0 stalls in 120 modals); (b) DONE: matrix-08 319/320 (one external-input failure, rerun 3/3); (c) SR1 gallery deferred | `examples/BridgeSmoke/result-smoke-rev08.txt`, `result-smoke-timeout08.txt`, `examples/BridgeGeoModal/result-textgeom08.txt`, `result-modal08.txt`, `probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md` (`820eb26`, `840f9ec`); tuple 06 receipts (`541129c`, `5a67f23`) are history |
| R2 Windows build/sign | DONE on tuple 08: MSIX 0.1.0.0 `c80c6947…` (from `a6d657b`) / 0.1.1.0 `0ff65165…` (clone-local `5e6338b6`), signed, swift-only proof ok, `@rightkit/release` 0.2.146. The Windows signing certificate used (thumbprint `121FD7B5…`) expires 2026-10-12 05:16:54 Dell local; a new Windows build needs a renewed certificate | `examples/SliceApp/RESULT-R5-08.md` (`d4d2ca4`); tuple 06 pair `RESULT-R5.md` and the R2 pair `RESULT-R2.md` are history |
| R3 Mac build/sign | DONE: final DMG 0.1.0 `b976ac70…` and 0.1.1 `75f3cd75…` on `@rightkit/release` 0.2.144, QA receipts passed, codesign, spctl, stapler and syspolicy_check pass; repo records committed. The Mac does not use the renderer, so tuple 08 changes nothing here | `examples/SliceApp/r3-final/`, `r3-final-011/` (`34e818a`, `0be0ea3`); earlier DMGs in `examples/SliceApp/PACKAGING.md` |
| R4 RightKit publish | DONE; SliceApp pinned to `@rightkit/release` 0.2.146 (Windows tuple 08 build; Mac DMGs 0.2.144) | `a6bc045` (0.2.146), `f4c313f` (0.2.144) |
| R5 Windows clean guest | RUN on tuple 08: offline **13/14, W08 FAIL**; network W00/W01/W12 PASS. W08: update cancelled in the registration phase leaves the package `NeedsRemediation`, data intact; no manual Repair during the 10-min hold, platform `RegisterByPackageFullName` at hold end. RightKit documented the recovery (`@rightkit/release` README `e93ac2df`). Closes with the decision to accept it as a known limitation | `examples/SliceApp/RESULT-R5-08.md`, `qualification/receipts/package/win-r5-08-*` (`d4d2ca4`) |
| R6 Mac oracle (signed recorder) | after Adrian creates the test user + AX grant | separate macOS user via Remote Desktop | Re-record F1–F9 with the signed recorder; cross-platform compare on the 0.6 tuple | 0 diffs, recorder identity recorded |
| R7 Mac clean environment | DONE: install, upgrade, rollback, corrupt-update rejection, uninstall-keeps-data, Gatekeeper baseline, interrupted install on 0.2.142 and the quarantined first launch of the R3 final DMG (stapled `.app`, 10/10 online and offline) PASS in a clean Tart VM | `examples/SliceApp/RESULT-R7.md` (`c7ddb7d`, `94b81ac`, `2403117`) |
| R8 Automation | Runner hardened and run on tuple 08 on the Dell: win-replay, compare, smoke, package (results in `docs/sr0-status.md`, files `qualification/out/r8-tuple08/`); mac-oracle stage PENDING with R6 (needs the Mac free); F6 A/B decision open | `1b7cdc1`, `2c8b765`, `docs/qualification.md`, `qualification/tuple-final.json` (tuple 08) |
| R9 Native interaction | DONE except Narrator speech: on tuple 08 IME F7 20/20, F7live 20/21, F8 18/19 (only `candidate-window-follows-layout-move`; limitation routed to SR1), Narrator 8/8 automatable | `probes/sr0-b/native-interaction/out/*-tuple08.txt` (`840f9ec`). Speech: a person listening, about 2 min, PENDING (Adrian) |
| R10 §11 workload | Windows run on tuple 08: all thresholds pass except W5 zero missed vblanks (5, 1, 1 per 60 s run); leak slope 3.21-4.42 MB/min PASS; lane done criterion is "met or reported". PENDING: one run with the NVIDIA overlay off (Adrian) and a Mac windowed result. Measured under normal host use (policy change, `65cd886`) | `probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt` (`840f9ec`), `ITERATION.md` |
| R11 Freeze & close | PENDING: freeze proposals are bound to tuple 08 and stay NOT FROZEN (`docs/sr0-freeze-slice-contract-v1.md`, `docs/sr0-freeze-bridge-interface.md`) with the known limitations listed; `CONTRACT.md` is still DRAFT v0.1 | Closes when R6 is receipted and W08 and W5 are accepted as limitations (or repaired), and C1-C8 are applied |

Runs alongside each other: R0, R2-prep, R3-prep, R4, R5-prep, R7-prep, R8 start immediately. Desktop-bound lanes (R1, R5 run, R9, R10) share the Dell desktop in that order. Timing lanes (R10) need quiet hosts: no builds or other GUI work during them.

## Adrian's actions

1. Restart the Dell now (matrix finished) so Windows Sandbox is active.
2. Create a separate macOS user for testing, enable Remote Desktop/Screen Sharing for it, and grant Accessibility to `F1MacRecord.app` inside that user.
3. Provide a clean macOS VM or second clean user for R7.
4. Be at the Dell for ~5 minutes of real Japanese IME typing in R9 when asked.

## Done criteria

Every `docs/sr0-status.md` row PASS with receipts bound to the snapshot manifest; contract v1.0 and ABI 0.6 frozen; signed DMG and MSIX verified and clean-machine checked; §11 workload thresholds met; automation runner green with no skips.

## Lane status (11 October 2026, HEAD `61be5f94`, final tuple 11)

Every state cites a committed file or commit; PENDING has no committed result. Receipts carry between tuples only where the binaries are byte-identical (`docs/sr0-snapshot.md` section 2e). Performance bar: Adrian dropped the zero-missed-vblank criterion on 2026-10-10 (`docs/sr0-findings.md` section 11, `docs/architecture.md` §11 revision 2).

| Lane | State | Evidence / what closes it |
|---|---|---|
| R0 Evidence & snapshot | DONE (kept current) | `docs/sr0-snapshot.md` (final tuple 11, section 2e; rerun state 5b), `docs/sr0-retry-ledger.md`, status and freeze docs |
| R1 Dell desktop | (a) DONE, carried from tuple 09 (byte-identical binaries): smoke 40/40, timeout 41/41, pixel assertions 10/10 on two capture methods, text geometry 20/20, real modal paths 20/20 (0 stalls in 120 modals); (b) DONE on tuple 11: matrix **320/320 first attempt**; (c) SR1 gallery deferred | `examples/BridgeSmoke/result-smoke-rev09.txt`, `result-smoke-timeout09.txt`, `result-smoke-pixels09.txt`, `result-bridgepixels09.txt`; `examples/BridgeGeoModal/result-textgeom09.txt`, `result-modal09.txt`, `result-coldopen09.txt`; `probes/sr0-s/fresh-on-bridge/out/matrix-11/RESULT.md:7` (`2f71a1cd`, `2c84c0f4`); tuple 06 to 08 receipts are history |
| R2 Windows build/sign | DONE on tuple 10 (the tuple 11 member): MSIX 0.1.0.0 `39007039…` (from `0a745ab`) / 0.1.1.0 `efc52869…` (clone-local `c60b1377`), signed, swift-only proof ok, `@rightkit/release` 0.2.146. The signing certificate (thumbprint `121FD7B5…`) expires 2026-10-12 05:16:54 Dell local; a new Windows build needs a renewed certificate | `examples/SliceApp/RESULT-R5-10.md` (`ea5fbe25`); tuple 06 to 09 pairs are history |
| R3 Mac build/sign | DONE: final DMG 0.1.0 `b976ac70…` and 0.1.1 `75f3cd75…` on `@rightkit/release` 0.2.144, QA receipts passed, codesign, spctl, stapler and syspolicy_check pass; repo records committed. The Mac does not use the renderer, so tuples 08 to 11 change nothing here | `examples/SliceApp/r3-final/`, `r3-final-011/` (`34e818a`, `0be0ea3`) |
| R4 RightKit publish | DONE; SliceApp pinned to `@rightkit/release` 0.2.146 for the Windows build (`examples/SliceApp/package.json:8`); Mac DMGs built on 0.2.144 | `a6bc045` (0.2.146), `f4c313f` (0.2.144) |
| R5 Windows clean guest | RUN on the tuple 10 pair: offline **13/14, W08 FAIL**; network W00/W01/W12 PASS first attempt. W08: update cancelled in the registration phase leaves the package `NeedsRemediation`, data intact. **Three user recoveries measured on the final packages** (Settings Repair, same-version `Add-AppxPackage -Path`, same-version `-AppInstallerFile`); `Reset-AppxPackage` and the platform's own registration do not recover. Closes with the decision to accept it as a known limitation, or repair and rerun | `examples/SliceApp/RESULT-R5-10.md`, `RESULT-R5-W08-recovery-08.md`, `qualification/receipts/package/win-r5-10-*` (`ea5fbe25`, `3587dcc1`) |
| R6 Mac oracle (signed recorder) | Mac side DONE (`593e3ab`): mac-oracle 16 configs x 3 equal the accepted baselines; signed F1 re-record 0 diffs; F6 100-run sample 96 / 4, decided as unordered (proposed C9). Cross-compare of all 16 configs: tuple 10 11/16 (F6 passes under proposed C11; 5 configs fail on launch selection); **tuple 11 compare: running, no committed result (placeholder line in `docs/sr0-status.md`)**. R5, R6, R8 unproven; P2 settled as a Mac quirk | `probes/sr0-o/R6-RESULT.md`, `probes/sr0-o/F6-UNORDERED.md`, `probes/sr0-o/f1-cross/CROSS-ALL.md` (`7a755ad1`). Closes with the committed tuple 11 compare and the unproven items accepted or proved |
| R7 Mac clean environment | DONE: install, upgrade, rollback, corrupt-update rejection, uninstall-keeps-data, Gatekeeper baseline, interrupted install on 0.2.142 and the quarantined first launch of the stapled-`.app` build (10/10 online and offline) PASS in a clean Tart VM | `examples/SliceApp/RESULT-R7.md` (`c7ddb7d`, `94b81ac`, `2403117`) |
| R8 Automation | Runner hardened; last full run on tuple 08 (win-replay 48/48, compare F1 0 diffs, smoke, package macOS 12/12, Windows FAIL only on W08). Since: closure gate adds `workload` and `native` stages and requires all 16 compare configs (`32536d98`); F6 canonical mirror of C9 in `run.py`; `tuple-final.json` names tuple 11. **No runner run on tuple 11 is committed (PENDING)** | `qualification/out/r8-tuple08/`, `qualification/run.py`, `qualification/tuple-final.json`, `docs/qualification.md` |
| R9 Native interaction | Tuple 10 files (superseded fixture host): IME F7 17/20 then 20/20 (one flaky run), F7live 20/21, F8 18/19 (only `candidate-window-follows-layout-move`, limitation routed to SR1), Narrator 8/8 automatable. **Tuple 11 run: running, no committed result (placeholder line in `docs/sr0-status.md`).** Narrator speech: a person listening, about 2 min, PENDING (Adrian) | `probes/sr0-b/native-interaction/out/*-tuple10*.txt` (`0c0a4f93`); tuple 09 `*-tuple09.txt` (`2f71a1cd`) |
| R10 §11 workload | Windows run on tuple 10 (byte-identical on tuple 11): all thresholds pass except the dropped W5 zero-miss gate; missed vblanks 1, 1, 1 per 60 s reported; W4 p95 46.37-48.83 ms and interval p95 16.73-16.74 ms against Mac SwiftUI 71.6-78.9 ms and 17.82-17.94 ms; leak slope 1.72 / 3.90 / 4.20 MB/min (close to 5.0 in 2 of 3 runs). Overlay-off run no longer gating. Mac windowed run done with its caveats | `probes/sr0-b/workload/results/r10-20261011-tuple10-renderere280-windows.txt`, `MAC-WORKLOAD.md`, `W5-EXPERIMENTS.md` (`0c0a4f93`, `3ef265bd`, `b4ab3bf3`) |
| R11 Freeze & close | PENDING: freeze proposals are bound to tuple 11 and stay NOT FROZEN (`docs/sr0-freeze-slice-contract-v1.md`, `docs/sr0-freeze-bridge-interface.md`); `CONTRACT.md` is still DRAFT v0.1 with proposed C9 and C11 text only | Closes when the tuple 11 compare and R9 are receipted, Narrator is listened to, W08 is accepted (or repaired), the retry overruns are recorded, and C1-C8, C3, C9-C11 are applied; exact list in `docs/sr0-freeze-slice-contract-v1.md` section 4 |

Remaining user-dependent items (11 Oct): Narrator listen (about 2 min at the Dell); the decision to accept W08 as a known limitation; the record of the retry-cap overruns; certificate renewal before any new Windows build. Running now: tuple 11 cross-compare and tuple 11 R9.
