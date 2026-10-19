Last updated: 2026-10-19 (tuple 13 qualified; freeze #22 waits on Adrian)

State (19 Oct 2026): tuple 13 QUALIFIED (`docs/sr0-status.md` top, `qualification/tuple13-candidate.json`): renderer `1aa8ad22…` (TextCache byte budget, #34), rebuilt MSIX, single combined run r3 all stages PASS. Tuple 12 (renderer `7578cd5d…`) failed R10 on the leak flag and is superseded.
# SwiftRight — pending (SR0 close-out lane)

| # | Item | State |
|---|---|---|
| A | Stage tuple 12 | Windows Full16x20 320/320 qualified 2026-10-13 (matrix-v1/RESULT.md). Canonical stage commit `a9556b77f50315afcae27fc8fc44c0cd274959e2` (17 Oct). Renderer admitted; FreshOnBridge `87b8cb27…` stays the tuple member. Build-only canonical stage at `D:\Claude\swiftright\.work\sr0-r12` may proceed after parse preflight, Dell process/task/lock audit and peer messages; still pending: its stage receipts with source/render/member hashes |
| A1 | Admit recovered renderer artifact | ADMITTED 17 Oct: DLL `7578cd5d…` (11,887,616 B) at sealed path `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll`; `Cargo.lock` `0e28d8bb…` admitted under the lock-parse rule (same lockfile v4 and 720 package entries as source lock `a8716a98…`; 11 non-lock source files byte-identical; both lock hashes recorded). Receipts: recovery `status-jobs1-r3.stdout.bin`, seal `seal-managed-renderer-r3.stdout.bin`. Decision: `docs/sr1-decisions.md` |
| B | W08: cancelled MSIX update leaves app unopenable (FIXED: repair guard accepted by Adrian 18 Oct, #19 closed) | Tier 2 repair guard on `@rightkit/release` 0.2.156 (guard sha256 `5abc0a4d...`, RightKit `1cf6ab31`), release-signed pair 0.1.0.0 run 38551981243 / 0.1.1.0 run 38552030862, Sandbox only: r-a cancel at 360 ms left `Modified, NeedsRemediation`, repaired to 0.1.1.0 Ok at +12.3 s with no action of ours, launch OK, data hash unchanged; fd-a (feed down), wrongid and corrupt were refused, logged and then repaired by the retry; uninst and uninst-retry removed task and folder, user data kept. Oracle review 17 Oct PASS-WITH-CAVEATS; acceptance decision Adrian's (issue #19). Evidence: `docs/sr0-w08-upstream-handoff.md`, `qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/RECEIPT.md`. Not proven: a real cancel on a real PC, a non-admin user, Task Scheduler blocked by policy |
| C | Requalify tuple 12 | Superseded by tuple 13 (19 Oct): tuple 12 failed R10 (leak flag); tuple 13 qualified, all stages in run r3 |
| 1 | Prior qualification runner | tuple 13 qualified through `qualification/tuple13-run.sh` (run r3, exit 0) |
| 2 | Dell stage trees | tuple 13 Dell trees under `D:\Claude\swiftright\.work\sr0-r13\` (workload, smoke, typecheck/src); nothing deleted |
| 3 | Narrator speech content | Adrian will listen later |
| 4 | W08 | must be fixed, not accepted as limitation |
| 5 | Comparison repeat count | accepted: 20 Mac & 20 Windows per config on final 0.6 tuple |
| 6 | Freeze | W08 closed 18 Oct; tuple 13 qualified 19 Oct: freeze decision is Adrian's (#22) |
| 7a | Tuple 12 packages (MSIX/DMG) | Tuple 13 packages signed (CI runs 39220477732 / 39220481624: Windows Azure OIDC, macOS Developer ID + notarized), qualification only, no publication |
| 7 | Signing | new-package signing approved using short-lived Azure certificate reissue; no fixed expiry deadline |
| 8 | Unproven recorder items | R8 settled, R5 closed, R6 accepted limitation per current decision record |
| 9 | Selection highlight not painted | Confirmed 19 Oct with two capture methods (GDI screen copy and PrintWindow PW_RENDERFULLCONTENT, tuple 13 build): after launch focus neither the selection highlight nor the caret is drawn, while UIA reports focus 0+5 (`probes/sr0-s/fresh-on-bridge/out/tuple12-selection-shot-sbx1/`). Accepted SR0 limit; SR1 fixes it (#25) |
| 10 | Renderer ready metrics | in the tuple 13 build (stage a9556b77f); Full16 x20 320/320 on tuple 13 |
| 11 | IME candidate list after layout move | Dropped for SR0 (19 Oct, #24): the held IMM32 patch reopens the renderer (tuple 13) at ~25% expected effect; the native gate keeps `candidate-window-follows-layout-move` as the one allowed FAIL. SR1 carries the TSF ITextStoreACP design (docs/held-patches/swiftright-03-ime-candidate-follow.md, outline b) |
| 12 | SR1 factory | owned by Codex factory session; renderer/ABI edits remain held until SR0 closes |

Four user decisions currently govern close-out: 20-per-side comparison is accepted; W08 must be fixed, not accepted (guard-vs-upstream is Adrian's open decision, issue #19); freeze remains held; Narrator listening happens later.
