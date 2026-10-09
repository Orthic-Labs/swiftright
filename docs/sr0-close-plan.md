# SR0 close plan (v2)

9 October 2026, revised after an adversarial Astra review of v1. Goal: close SR0 with receipts that cannot be false-green. SR1 work stays paused until SR0 closes unless Adrian says otherwise.

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
