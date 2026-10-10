# SR0 close plan (v2)

9 October 2026, revised after an adversarial Astra review of v1. Goal: close SR0 with receipts that cannot be false-green. SR1 work stays paused until SR0 closes unless Adrian says otherwise.

**Status 10 October 2026 (HEAD `4496474`): SR0 is open; lane states are in "Lane status" at the end of this file. The plan text between is unchanged and is the plan, not the state.** Current state: `docs/sr0-status.md`; tuple: `docs/sr0-snapshot.md` section 2c.

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
| R1 Dell desktop | after Dell restart | Dell interactive (1 at a time) | (a) 0.6 BridgeSmoke + timeout mode; (b) matrix on 0.6 tuple incl. F3 3 s variants, 20 runs each; (c) SR1 gallery deferred | All configs 20/20 on the snapshot tuple |
| R2 Windows build/sign | now (prep) → after F1 fix | Dell via SSH, independent clean clone | Old + new MSIX, renderer staged, sign + verify, Swift-only rebuild proof (renderer bytes unchanged, zero Rust compiles) | All package checks pass with hashes |
| R3 Mac build/sign | now (prep) → after snapshot | Mac headless, independent clean clone | Old + new .app + DMG, sign, notarize, staple, verify | codesign/spctl/stapler pass |
| R4 RightKit publish | now | RightKit Mac | Publish @rightkit/release 0.2.138; then final rebuild R2/R3 on the pin, feeding R5/R7 | Final packages built from the published pin |
| R5 Windows clean guest | prep now; run after restart + R2 | Windows Sandbox | Install, offline launch, upgrade, real interrupted update, corrupt update rejection, rollback readability, uninstall keeps data, virtualization physical paths | Each check passes with logs + hashes |
| R6 Mac oracle (signed recorder) | after Adrian creates the test user + AX grant | separate macOS user via Remote Desktop | Re-record F1–F9 with the signed recorder; cross-platform compare on the 0.6 tuple | 0 diffs, recorder identity recorded |
| R7 Mac clean environment | prep now; run after R3 | clean macOS VM or user (Adrian provides) | Same checks as R5, quarantined delivery, offline first launch | Each check passes |
| R8 Automation | now | Mac (+ Dell when free) | Fix F3/F4; add smoke + package stages; strict exit; re-verify baselines | Runner fails on any skip/missing evidence; full run green |
| R9 Native interaction | after R1(b) | Dell desktop + Adrian for real IME | Real Japanese IME on the 0.6 tuple; Narrator/NVDA caret and actions | Logged pass with model-state effects |
| R10 §11 workload | after R1(b), quiet host | Dell desktop + Mac test user | 200-row workload, 10 s warm-up, 3×60 s, all thresholds, raw samples | Every threshold met or reported |
| R11 Freeze & close | join | — | Freeze contract v1.0 + ABI 0.6 on the snapshot; status PASS per stage | All lanes done |

Runs alongside each other: R0, R2-prep, R3-prep, R4, R5-prep, R7-prep, R8 start immediately. Desktop-bound lanes (R1, R5 run, R9, R10) share the Dell desktop in that order. Timing lanes (R10) need quiet hosts: no builds or other GUI work during them.

## Adrian's actions

1. Restart the Dell now (matrix finished) so Windows Sandbox is active.
2. Create a separate macOS user for testing, enable Remote Desktop/Screen Sharing for it, and grant Accessibility to `F1MacRecord.app` inside that user.
3. Provide a clean macOS VM or second clean user for R7.
4. Be at the Dell for ~5 minutes of real Japanese IME typing in R9 when asked.

## Done criteria

Every `docs/sr0-status.md` row PASS with receipts bound to the snapshot manifest; contract v1.0 and ABI 0.6 frozen; signed DMG and MSIX verified and clean-machine checked; §11 workload thresholds met; automation runner green with no skips.

## Lane status (10 October 2026, HEAD `4496474`)

Every state cites a committed file or commit; PENDING has no committed result.

| Lane | State | Evidence / what closes it |
|---|---|---|
| R0 Evidence & snapshot | DONE (kept current) | `docs/sr0-snapshot.md` (final tuple section 2c), `docs/sr0-retry-ledger.md`, status and freeze docs |
| R1 Dell desktop | (a) DONE: smoke 40/40, timeout mode 41/41 on the final renderer; (b) DONE: matrix 320/320 first time on the final tuple; (c) SR1 gallery deferred | `541129c` (`examples/BridgeSmoke/result-smoke-rev06final.txt`, `result-smoke-timeout06final.txt`), `5a67f23` (`probes/sr0-s/fresh-on-bridge/out/matrix-final/RESULT.md`) |
| R2 Windows build/sign | DONE on the final renderer pin: MSIX 0.1.0.0 `4cc9a7f0…` / 0.1.1.0 `c2897a68…` from `0751951`, signed, swift-only proof ok. The Windows signing certificate used (thumbprint `121FD7B5…`) expires 2026-10-12 05:16:54 Dell local; a new Windows build needs a renewed certificate | `examples/SliceApp/RESULT-R5.md` (`4496474`); old pair `RESULT-R2.md` (`b476c85`) is history |
| R3 Mac build/sign | DONE: final DMG 0.1.0 `b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4` on commit `4496474` with `@rightkit/release` 0.2.144, QA source receipt passed, codesign, spctl, stapler and syspolicy_check pass for DMG and `.app` (coordinator report 10 Oct; receipts read and hash recomputed). Repo record PENDING; 0.1.1 not rebuilt on the final pin | `/Volumes/D/sr0-artifacts/mac/r3-final/` (outside the repository); earlier 0.2.139 and 0.2.142 DMGs in `examples/SliceApp/PACKAGING.md` |
| R4 RightKit publish | DONE; SliceApp pinned to `@rightkit/release` 0.2.144 | `f4c313f` (0.2.143 `b5473b9`) |
| R5 Windows clean guest | RUN, **14/15: W08 FAIL** (update cancelled ~240 ms after staging leaves the package `NeedsRemediation`; data intact). Routed to RightKit; recovery probe pending | `examples/SliceApp/RESULT-R5.md`, `4496474`. Closes with the RightKit probe result and a decision (accept as limitation, or RightKit repair and rerun) |
| R6 Mac oracle (signed recorder) | PENDING | Plan text assumed a separate macOS user; the current need is the Mac free about 10 min (lead, 10 Oct), recorder signed (`7a91608`), Accessibility grant reported done (no committed record). Closes with the F1-F9 re-record, cross-compare and the 100-run F6 sample committed |
| R7 Mac clean environment | RUN, partial: install, upgrade, rollback, corrupt-update rejection, uninstall-keeps-data, Gatekeeper baseline (0.2.139) and interrupted install on 0.2.142 PASS; quarantined launch on the stapled-`.app` build PENDING | `examples/SliceApp/RESULT-R7.md` (`c7ddb7d`, `94b81ac`) |
| R8 Automation | Runner hardened (canonical v2, strict exit, receipt schema v2); full run on the final tuple PENDING; F6 A/B decision open | `1b7cdc1`, `2c8b765`, `docs/qualification.md` |
| R9 Native interaction | DONE except Narrator speech: IME F7 20/20, F7live 20/21, F8 18/19 (limitation routed to SR1), Narrator 8/8 automatable | `541129c` (`probes/sr0-b/native-interaction/out/*-tuplefinal.txt`). Speech: a person listening, about 2 min (Adrian), PENDING |
| R10 §11 workload | Windows run: all thresholds pass except W5 zero missed vblanks (1-3 per 60 s run); lane done criterion is "met or reported". PENDING: one run with the NVIDIA overlay off (Adrian); it6-it8 result files and a Mac windowed result are not committed. Measured under normal host use (policy change, `65cd886`) | `probes/sr0-b/workload/results/ITERATION.md`, `33987c2` |
| R11 Freeze & close | PENDING: contract v1.0 and ABI 0.6 freeze proposals are bound to the final tuple (`docs/sr0-freeze-slice-contract-v1.md`, `docs/sr0-freeze-bridge-interface.md`) with the known limitations listed; `CONTRACT.md` is still DRAFT v0.1 | Closes when R6, R8, R10 W5 and R5 W08 are receipted or accepted as limitations and C1-C8 are applied |

Remaining Adrian actions (10 Oct): the Mac free about 10 min for R6; about 2 min listening to Narrator speech at the Dell; one R10 run with the NVIDIA overlay off; the decisions named in the ledger's resume section (R10 W5, W08).
