Last updated: 2026-10-17 (W08 row B and governing sentence: 0.2.156 guard evidence and Oracle review PASS-WITH-CAVEATS, issue #19)

State (17 Oct 2026): renderer ADMITTED under the lock-parse rule (`docs/sr1-decisions.md`, 17 October: tuple 12 stage identity and renderer admission). Renderer `7578cd5d…` (11,887,616 B) staged from sealed path `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll`; broker-rewritten `Cargo.lock` `0e28d8bb…`. Canonical stage commit `a9556b77f50315afcae27fc8fc44c0cd274959e2`. Recovery receipt `probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/status-jobs1-r3.stdout.bin`; seal receipt `probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/seal-managed-renderer-r3.stdout.bin`. No tuple 12 qualification receipt exists yet. Transferred no-delete scripts remain archived under `probes/sr0-s/fresh-on-bridge/out/tuple12-stage-takeover-r1`. Tuple 11 is last qualified baseline.
# SwiftRight — pending (SR0 close-out lane)

| # | Item | State |
|---|---|---|
| A | Stage tuple 12 | Windows Full16x20 320/320 qualified 2026-10-13 (matrix-v1/RESULT.md). Canonical stage commit `a9556b77f50315afcae27fc8fc44c0cd274959e2` (17 Oct). Renderer admitted; FreshOnBridge `87b8cb27…` stays the tuple member. Build-only canonical stage at `D:\Claude\swiftright\.work\sr0-r12` may proceed after parse preflight, Dell process/task/lock audit and peer messages; still pending: its stage receipts with source/render/member hashes |
| A1 | Admit recovered renderer artifact | ADMITTED 17 Oct: DLL `7578cd5d…` (11,887,616 B) at sealed path `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll`; `Cargo.lock` `0e28d8bb…` admitted under the lock-parse rule (same lockfile v4 and 720 package entries as source lock `a8716a98…`; 11 non-lock source files byte-identical; both lock hashes recorded). Receipts: recovery `status-jobs1-r3.stdout.bin`, seal `seal-managed-renderer-r3.stdout.bin`. Decision: `docs/sr1-decisions.md` |
| B | W08: cancelled MSIX update leaves app unopenable | Tier 2 repair guard on `@rightkit/release` 0.2.156 (guard sha256 `5abc0a4d...`, RightKit `1cf6ab31`), release-signed pair 0.1.0.0 run 38551981243 / 0.1.1.0 run 38552030862, Sandbox only: r-a cancel at 360 ms left `Modified, NeedsRemediation`, repaired to 0.1.1.0 Ok at +12.3 s with no action of ours, launch OK, data hash unchanged; fd-a (feed down), wrongid and corrupt were refused, logged and then repaired by the retry; uninst and uninst-retry removed task and folder, user data kept. Oracle review 17 Oct PASS-WITH-CAVEATS; acceptance decision Adrian's (issue #19). Evidence: `docs/sr0-w08-upstream-handoff.md`, `qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/RECEIPT.md`. Not proven: a real cancel on a real PC, a non-admin user, Task Scheduler blocked by policy |
| C | Requalify tuple 12 | matrix 320/320 done (stays valid, bound to EXE `87b8cb27…`, renderer `7578cd5d…`, source manifest `f45b9e0d…`); Windows cross x20 301/320; the remaining 19 cross recordings (F7 r11, F8 r20, F9 r4-20) wait for Adrian; Mac refs only F1; still pending: matrix, smoke, pixels, text, modal, R9, R10, package & 20 Mac/20 Windows recordings per config; use tuple12 manifest candidate only after all hashes are receipted |
| 1 | Prior qualification runner | tuple 11 automation remains historical baseline; tuple 12 runner launch/replay wrapper is prepared, no tuple 12 run |
| 2 | Dell stage trees | prior paths corrected; tuple12 root currently absent, no deletion performed |
| 3 | Narrator speech content | Adrian will listen later |
| 4 | W08 | must be fixed, not accepted as limitation |
| 5 | Comparison repeat count | accepted: 20 Mac & 20 Windows per config on final 0.6 tuple |
| 6 | Freeze | held until W08 & tuple12 qualification close |
| 7a | Tuple 12 packages (MSIX/DMG) | UNSIGNED candidates built (CI run 38411495413, `498f9d94`; MSIX `5605d93c…`, DMG `cb4e63a5…`; Sandbox smoke PASS; `docs/sr0-status.md`). Remaining: Adrian provisions `release` env secrets + Azure federated credential `repo:Orthic-Labs/swiftright:environment:release`; signed-lane hand-off from the unsigned candidate; tuple 12b rebuild after the W08 guard lands; SR0-P package run + W08 proof |
| 7 | Signing | new-package signing approved using short-lived Azure certificate reissue; no fixed expiry deadline |
| 8 | Unproven recorder items | R8 settled, R5 closed, R6 accepted limitation per current decision record |
| 9 | Selection highlight not painted | SR1-owned limitation; unchanged |
| 10 | Renderer ready metrics | tuple12 source candidate includes applied fix; stage/requalification pending |
| 11 | IME candidate list after layout move | SR1/RightKit-owned limitation; unchanged |
| 12 | SR1 factory | owned by Codex factory session; renderer/ABI edits remain held until SR0 closes |

Four user decisions currently govern close-out: 20-per-side comparison is accepted; W08 must be fixed, not accepted (guard-vs-upstream is Adrian's open decision, issue #19); freeze remains held; Narrator listening happens later.
