# COLD-START HANDOFF: SwiftRight SR0+SR1 lead, 16 October 2026 close-of-day

## 0. Handoff Control

- **Handoff ID:** swiftright-sr0-sr1-lead-20261016
- **Created:** 2026-10-17T04:45:00+05:30
- **Source task / chat:** Claude Code session `720f96f5-3f75-4a4b-a078-dd6e86d05cf8` (self-named "swiftright-a8"; Adrian calls it the "SR0" chat), workspace `/Volumes/D/claude/swiftright`, 2026-10-13T04:14Z to 2026-10-16T17:51Z
- **Target:** cold Claude Code chat in `/Volumes/D/claude/swiftright` (this packet was authored by the target session `swiftright-a6`, Claude Code session `49644702-cd60-4ca0-a22d-85e40dcb1213`)
- **Author:** Legion (target chat swiftright-a6), TRANSCRIPT_INGEST from typed Legion context, live state re-read 2026-10-17 04:32 to 04:45 IST
- **Receiver role:** CONTINUATION (SR0 close-out + SR1 parity factory lead + Pulse hub Windows port support)
- **Proceed mode:** IMMEDIATE
- **Readiness:** READY_WITH_GAPS
- **Handoff reason:** source chat reached the end of its 16 October lanes (all landed on `master` at `b0927b27e`, Oracle PASS, no agents running) and its context was large (16.2 MB transcript); it invoked `/handoff` to move the lead to a fresh chat.
- **Source evidence mode:** TRANSCRIPT_INGEST
- **Transcript evidence path:** `/Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/720f96f5-3f75-4a4b-a078-dd6e86d05cf8.context.json` (receipt `720f96f5-3f75-4a4b-a078-dd6e86d05cf8.context.receipt.json` beside it, RECEIPT_PASS 2026-10-17 04:32 IST; 1606 events, 41 user requests, 8557 omissions all `recoverable` tool-result/reasoning elisions)
- **Source prefix receipt:** PLATFORM:claude SESSION_ID:720f96f5-3f75-4a4b-a078-dd6e86d05cf8 CUTOFF_BYTES:16187620 SHA256:8ff5cb630727c8c2a6f2d0d660b1506b1c303a49c67933005681f588082d3b94 PARSER_VERSION:legion.transcript-event.v1
- **Packet path:** `/Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.md`
- **Receipt path:** `/Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.receipt.json`

## 1. Intent & Mission

- **Original user intent verbatim:** The source chat opened on 2026-10-13 with Adrian's pasted handover, whose first actions were: "FIRST ACTIONS: (1) reconcile and push git; (2) confirm with Adrian who owns the work now and get the 0.7 / font decisions in writing; (3) then finish the five blocks before any scaling." Adrian's corrections during the chat, verbatim: "I needed you to close sr0 and 1 and make progress but you've reported and stopped?" (13 Oct); "can you not do it all in the sandbox? this constant flashing and foregrounding is really messing with my work" (13 Oct); "i aint doing shit for Azure, you figure it out bud" (14 Oct); "i need to know what's next at every turn" (14 Oct); "the first one can be pulse, it's notch is swift if i remember right, it also has a native/ gpui version today. I think. you can check the repo. THat's the best first candidate" (14 Oct); "pleae mark swiftright as apache 2.0, that's the right one allowing reuse right?" (15 Oct); "please close the old subagents and start new ones. are they haiku?" (15 Oct); "ok, then lets do local builds for now, as long as they're iterative and quick." (15 Oct); "i dont see any action" (16 Oct); "we good?" (16 Oct, last message before the handoff). Source chat's own handoff brief: "SwiftRight SR0+SR1 lead (session swiftright-a8) handoff to a cold chat. All lanes from 16 Oct have landed on master at b0927b27e; no agents running."
- **Underlying goal:** SwiftRight runs the same SwiftUI source on Windows (SwiftRight runtime + bridge + Rust/GPUI renderer) with Mac-SwiftUI parity proven per block by the SR1 factory (generate cases, capture Mac and Windows, compare, gate, independent review). SR0 (the SliceApp qualification tuple, packaging, W08) must close and freeze. The first real consumer is Pulse (hub in SwiftUI first, then the notch), so SR1 blocks are chosen by what the Pulse hub needs.
- **Current objective:** keep SR0 and SR1 moving without Adrian's involvement: (a) carry the 16 October review verdicts forward; (b) act on open GitHub issues #2 and #3; (c) get blocks 39 (uia-walk), 40 (ime-traps) and `foundations.image-layout` independently reviewed; (d) bring the five not-delivered blocks (7 toggle, 13 textfield, 20 color-scheme, 28 system-font, 34 textfield-axis) back to delivered; (e) keep SR0 close-out evidence current (W08 guard, tuple 12) so freeze can happen when Adrian accepts the guard.
- **Definition of success:** every SR1 block in `docs/proven-controls.json` is `delivered` or `delivered-with-caveats` with Oracle review recorded; issues #2 and #3 closed with evidence; `docs/sr1-status.md` and `docs/sr1-decisions.md` updated per change; all results committed by explicit path and pushed to `origin/master` with green `swiftright-ci` and `swift-host-tests`; SR0 freeze decision presented with W08 proof and tuple 12 requalification evidence.
- **Out of scope:** porting Pulse's own code into this repo (Pulse Swift chat owns the Pulse repo; SwiftRight only compiles probes from a pinned SHA under `probes/pulse-hub/`); SR2 to SR4 (full shell, installer, performance budgets) until SR1 blocks the hub needs are delivered; building signing or installer machinery inside the repo (RightKit owns it); any change to ABI/renderer ownership policy.
- **First responsibility:** verify live state (Resume Step 1), return READBACK, then check open issues and start the pending Oracle reviews.
- **Must not do first:** do not commit the 366 untracked run directories wholesale; do not run any windowed test on the Mac or foreground anything on the Dell; do not reopen the transaction semantics (decision H27) or hover placement (H25); do not ask Adrian a question that Astra or the repo can answer.

## 2. Current State

- **Phase:** SR1 round 6 closed and reviewed (blocks 37, 38, 41 delivered-with-caveats; 39, 40 delivered-pending-review); SR0 OPEN with W08 Tier-2 guard proven in the Sandbox but not accepted by Adrian; freeze held.
- **Completed:** (verified 2026-10-17 04:3x IST) `master` = `origin/master` = `b0927b27e` (0 ahead, 0 behind), no modified tracked files; CI on `b0927b27e` green: `swiftright-ci` run 38942843440 and `swift-host-tests` run 38942843234; Oracle final review of 16 Oct passed (transaction rework `7796b0b81`, hover H25/H26, flicker H19); `onchange-animation-v1` and `state-nested-update-v1` pass N=20 (run 38916914529), 39-case N=3 regression passes (run 38916920414); hover `adjacent-v1` 200/200 exact and `rows-v1` 220/220 edge-aa at N=20 (run 38916701641); W08 item (d) daily-mode retry fired 16 Oct 17:12 IST and re-armed (`6dab6cf67`); Apache 2.0 `LICENSE` in repo; local-build grant file pushed (`83056d3c6`); Pulse Swift notified that onHover and the animation semantics are safe on Windows (SendMessage 2026-10-16T17:47Z, msg `314293eb`).
- **In progress:** nothing running. The source chat's last Alchemist (registry recording) finished and produced `b0927b27e`. The source chat's last Oracle finished (PASS). 366 untracked capture run directories under `factory/pipeline/blocks-*` exist in the working tree (see §3 Dirty state); they are evidence from reruns and infrastructure-failed jobs that no committed `results.jsonl` row references, left uncommitted on purpose.
- **Blocked:** SR0 freeze: blocked on Adrian's acceptance of the W08 in-runtime repair guard versus an upstream RightKit fix (reserved decision, `PENDING.md` rows B, 4, 6) and on tuple 12 requalification items still open (`docs/sr0-status.md`: Windows cross x20 at 301/320, Mac refs only F1, R9/R10/package/Narrator open). Nothing else is blocked.
- **Not started:** Oracle review of blocks 39, 40 and `foundations.image-layout` (all `delivered-pending-review`); fixes for issues #2 and #3; re-delivery of not-delivered blocks 7, 13, 20, 28, 34 (block 7 and 13 fail by 1 px after the F2 body-font rebaseline, decision G70; 20, 28, 34 per their rows in `docs/sr1-status.md`); `docs/proven-controls.json` `statusDate` still reads 2026-10-15 although rows were updated 16 Oct.
- **Last action:** source chat, 2026-10-16T17:51Z: `legion script handoff/transcript-handoff bootstrap --platform claude --session-id 720f96f5-3f75-4a4b-a078-dd6e86d05cf8 --workspace /Volumes/D/claude/swiftright` (its first attempt with the runtime session id `aac102e0-...` failed with "no transcript matches platform, session ID, & workspace"; the transcript-file UUID worked).
- **Last observed result:** bootstrap produced the pointer with CUTOFF_BYTES 16187620 and the SHA-256 above; this target verified it (PASS, RECEIPT_PASS) on 2026-10-17 04:32 IST.
- **Active goal / plan:** continue SR1 and SR0 per §1 Current objective; next plan item is Resume Step 2 (issues) and Step 3 (Oracle reviews).
- **Post-cutoff directive (2026-10-17, relayed by the RK3 Mac lead as Adrian's order, received by the target chat after this packet's evidence cutoff):** "make sure all your chats are moving and closing issues, and everyhing in pending was to be added to issues, no build or tests till all coding has been done. all dependencies to be bought up to date". Concretely: take issues 2 and 3 with edit-only subagents; file every pending SR1 block, H-probe and plan item as a GitHub issue; update dependencies (lockfiles only); move the 366 untracked `runs/` directories under `/Volumes/D/scratch/swiftright-runs` and gitignore `runs/`; no CI pushes until coding is done, then one push. This directive takes precedence over the ordering in Resume Steps 2 to 4.
- **Current hypothesis:** NOT_APPLICABLE: no open diagnosis; the only unproven technical point (H19 flicker: PrintWindow artifact likely, sub-200 ms on-screen transient not ruled out) is closed with its limit on record and does not affect gating.

## 3. Environment & Active Work

- **Work type:** MIXED
- **Work mix detail:** Swift runtime/host code, Rust renderer, Python factory tooling, CI workflows, Markdown evidence docs
- **Workspace / repo:** `/Volumes/D/claude/swiftright`, remote `git@github.com:Orthic-Labs/swiftright.git`, visibility PUBLIC (`gh repo view` 2026-10-17)
- **Branch / version:** `master` (default branch `master`, not `main`)
- **Baseline revision:** `b0927b27e` "SR1 review 16 October: block 38 on-hover delivered-with-caveats (CI N=20 run 38916701641); block 41 compat transaction rework reviewed (PASS), onchange-animation-v1 added; H19 probe result (run 38913551485); H26, H27", committed 2026-10-16 23:20 IST
- **Dirty state:** `git status --short | grep -v '^??'` is empty; `git status --short | grep -c '^??'` = 366, all under `factory/pipeline/blocks-37-38` (90), `blocks-6-10` (71), `blocks-26-34` (46), `blocks-11-16` (37), `blocks-w1-i2` (33), `blocks-17-20` (31), `blocks-w1-f2` (15), `blocks-24-25` (14), `blocks-21-23` (12), `blocks-t0` (8) and similar `runs/<timestamp>/` directories. Commit a run directory only when a `results.jsonl` row you commit references it.
- **OS / shell:** macOS 27.0.0 (Darwin 27.0.0), zsh; Dell Windows reached by `win "<cmd>"` over SSH; Windows Sandbox on the Dell runs minimised for all Windows captures; GitHub Actions `windows-2025` and `xcode-27` runners for long batches (Swift 6.4.0 both sides).
- **Tools / dependencies:** Swift 6.4.0; Rust only via `rightkit cargo` / `rightkit remote windows cargo` (read `/Volumes/D/claude/docs/rules/rightkit.md` first); `@rightkit/release` 0.2.156 in `package.json` (0.2.162 available, not adopted); `@rightkit/ci` 0.2.43 (0.2.45 available); CI result download `python3 factory/tools/ci_fetch.py <run-id>`; pair capture `factory/tools/pair.py --sandbox --scale-guard strict`; final-closure runner `factory/pipeline/closure/run_final.py`; registry generator `factory/tools/proven-controls/generate.py` (`--check` drift mode); Mac scale pin `factory/tools/mac-scale-pin/ScalePin.swift`; workflows `.github/workflows/{ci,factory-pairs,probe-f0-text,release-candidate,render-windows,swift-host-tests}.yml`.
- **Services / processes:** none for SwiftRight on the Mac (checked `launchctl list`: only workspace-level `com.orthic.issue-wake`, `com.orthic.cc-post-relay` and a Pulse app entry). Dell Windows Sandbox state not re-checked this turn (the `timeout` command is absent on the Mac; use `win` directly).
- **Agents / tasks / threads:** none running. Source chat's Oracle (final review) and Alchemist (registry recording) both completed before the cutoff; their results are in `b0927b27e` and issues #2/#3. Peer sessions on this Mac (ListAgents 2026-10-17): Pulse Swift, Heard, Post, View, Cut, RK3 phase 3 plan validation, cc-post relay. Pulse Swift is the consumer chat that receives SwiftRight capability notices.
- **Scheduled work:** Dell: the W08 Tier-2 guard's product scheduled task (`<PFN>-Repair`, event 751 + logon + daily-mode retry) inside the Windows Sandbox long-run test (`qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/RECEIPT.md`: "long-run retry test STARTED, not finished"); `job-w08.ps1` holds `C:\sbq\state\longrun-active.json` and refuses other w08 jobs while it exists (`--break-long-run` overrides). The source chat checked the retry daily after 17:13 IST; item (d) is closed as of 16 Oct, so a further daily check is optional evidence, not a requirement. Mac: no crontab; no SwiftRight launchd jobs.
- **Credentials / access:** GitHub `release` environment secrets present by name only: `APPLE_API_ISSUER`, `APPLE_API_KEY`, `APPLE_API_KEY_BASE64`, `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_KEYCHAIN_PASSWORD` (set 2026-10-14). Azure signing uses the Dell's signed-in Azure CLI session (Adrian refused to provision Azure himself; never start a browser/Azure login). Mac signed recorder identity `com.orthiclabs.swiftright.f1macrecord`, team `6KLGD3LLKF`. Never print or inspect credential values.

## 4. Decisions, Invariants & User Corrections

| ID | Decision / invariant / correction | Source / why | Status | Reopen only when |
|---|---|---|---|---|
| DECISION-01 | Pulse is SwiftRight's first real consumer: Pulse hub in SwiftUI first, then the notch; Pulse Swift chat writes the hub, SwiftRight compiles it for Windows and turns gaps into blocks | Adrian 14 Oct ("the first one can be pulse..."); `docs/hub-track.md` | LOCKED | Adrian names a different first consumer |
| DECISION-02 | Local Mac/Dell builds are allowed for iterative, quick work (unit tests, short builds, one case at a time); long batches (N=20), full regressions, signing and publication run in CI | Adrian 15 Oct ("lets do local builds for now, as long as they're iterative and quick"); grant file commit `83056d3c6` | LOCKED | Adrian revokes the grant |
| DECISION-03 | All Windows captures run in the minimised Windows Sandbox on the Dell or on GitHub runners; nothing flashes or foregrounds on Adrian's desktop | Adrian 13 Oct ("this constant flashing and foregrounding is really messing with my work") | LOCKED | Adrian says the Dell desktop is free for a named run |
| DECISION-04 | SwiftRight is Apache 2.0 | Adrian 15 Oct; `LICENSE` in repo | LOCKED | Adrian states a different rule in writing |
| DECISION-05 | Every reply to Adrian ends with a "Next:" line (what, who, waiting on) | Adrian 14 Oct ("i need to know what's next at every turn"); memory `state-next-every-turn` | LOCKED | Adrian states a different rule in writing |
| DECISION-06 | Mechanical subagent work goes to Haiku (`legion:alchemist`); Oracle/Sage on Opus; never ask Adrian, escalate unresolved choices to Astra (`codex exec -m gpt-6-astra`) and log in `/Volumes/D/claude/decisions.md` | Adrian 15 Oct ("are they haiku?"); memories `swiftright-haiku-subagents`, `no-questions-escalate-astra` | LOCKED | Adrian changes model policy |
| DECISION-07 | W08 (cancelled MSIX update leaves app unopenable) must be fixed, not accepted; Tier-2 in-runtime repair guard is proven in the Sandbox on release-signed 0.2.156 packages; closure needs Adrian's acceptance of guard-vs-upstream and Oracle review | Original handover; `PENDING.md` rows B, 4; `docs/sr0-w08-upstream-handoff.md` | REVISIT_ON | Adrian states acceptance or picks the upstream RightKit path |
| DECISION-08 | Freeze of ABI 0.6 is held until W08 closes and tuple 12 requalifies; tuple 11 is the last qualified baseline; 20 Mac + 20 Windows runs per config accepted; Narrator listening deferred to Adrian | `PENDING.md` rows 5, 6, 3; `docs/sr0-status.md` | LOCKED | W08 and tuple 12 both close |
| DECISION-09 | Each state write commits under the innermost open transaction (inner wins); onChange writes inherit the triggering change's animation unless they open their own | commit `7796b0b81`, Oracle PASS 16 Oct (H27); measured against real SwiftUI run 38913665384 | LOCKED | a real-SwiftUI N=20 case contradicts it |
| DECISION-10 | On CI only (`GITHUB_ACTIONS`), the capture host is placed HWND_TOPMOST with NOACTIVATE before real pointer moves; Dell placement unchanged | H25, run 38916701641 | LOCKED | hover cases regress on CI |
| DECISION-11 | Glyph shapes are never gated; pixels gate exact or edge-aa <= 32 outside named glyph regions; semantic gate is the accessibility-tree comparison | `docs/sr1-decisions.md` decisions 2, 5 | LOCKED | never without a Sage design pass |
| DECISION-12 | Every Mac capture host is pinned to scale 2.5 (`ScalePin.swift`, decision C12); only runs made with the final pin count | `docs/sr1-status.md` 15 Oct | LOCKED | Adrian states a different rule in writing |
| DECISION-13 | H19 flicker is closed as a PrintWindow capture artifact with the 200 ms sampling limit on record; gating unaffected | H19, Oracle 16 Oct | LOCKED | a screen-side black frame is ever observed |
| DECISION-14 | Commit evidence by explicit paths only, never `git add -A`; files over 50 MB stay out of git; repo is PUBLIC so no secrets or private product facts in commits | Adrian 13 Oct; GitHub hard limit | LOCKED | Adrian states a different rule in writing |
| DECISION-15 | Block 27 layout-priority narrowing (non-Text children) was lifted 16 Oct on block-gate verdicts (eight text cases N=20, L1-L8) but not re-reviewed | `docs/proven-controls.json` row | ACTIVE_ASSUMPTION | Oracle review of the lift |

## 5. Artifacts & Evidence

| Artifact | Path / URL | Role | State | Version / hash | Validation + last checked |
|---|---|---|---|---|---|
| Proven-controls registry | `docs/proven-controls.json` (generated by `factory/tools/proven-controls/generate.py`) | machine-readable block status for the Pulse hub track | COMPLETE for 16 Oct verdicts; `statusDate` stale (2026-10-15) | at `b0927b27e` | 43 rows read 2026-10-17 04:40 IST: 5 not-delivered, 3 delivered-pending-review, rest delivered/with-caveats |
| SR1 status | `docs/sr1-status.md` | per-block gates, stages, caveats | COMPLETE through 16 Oct | `b0927b27e` | headings read 2026-10-17 |
| SR1 decisions | `docs/sr1-decisions.md` | decisions A1-A10, 1-19, C11-C12, G1-G72, H1-H27, L1-L8, INFRA-1 | COMPLETE through H27 | `b0927b27e` | tail read 2026-10-17 |
| SR0 status / pending | `docs/sr0-status.md` (14 Oct), `PENDING.md` and `STATUS.md` (11 Oct) | SR0 close-out lane state | COMPLETE but dated; W08 (d) closure of 16 Oct is only in `6dab6cf67` and the RECEIPT | `b0927b27e` | read 2026-10-17 |
| W08 Tier-2 receipt | `qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/RECEIPT.md` + `longrun/snapshots/*.json` | W08 guard proof on release-signed packages | COMPLETE for Sandbox proof; owner decision + Oracle open | guard sha `5abc0a4d...` | read 2026-10-17 |
| Consolidation results | `factory/pipeline/consolidation/results.jsonl`, `consolidation-table.json` | per-case CI result rows | COMPLETE, 41 rows added in `06ccd699f` | `b0927b27e` | diff summarised in source chat 2026-10-16 17:39Z: 41 rows, 0 fail |
| Closure results | `factory/pipeline/closure/results.jsonl`, `closure-table.json`, `logs/final-6459bb8cd-d243b1c9/` | blocks 1-20 milestone on stage `6459bb8cd-d243b1c9` | COMPLETE (milestone met on that stage, not re-proven at HEAD) | stage `6459bb8cd-d243b1c9` | Oracle 15 Oct |
| Pulse hub port map | `docs/pulse-hub-windows-port.md`, `docs/hub-track.md`, `docs/pulse-notch-demand-map.md` | gap list driving block selection | COMPLETE: 20 compile gaps closed by rounds 5-6; hub-track table (14 Oct) still says "in progress" for its three deliverables | `b0927b27e` | read 2026-10-17 |
| Open issues | https://github.com/Orthic-Labs/swiftright/issues/2 (completions inside open withAnimation; outer completion early) and /issues/3 (ime-recompose-v1 pixel gate exemption check) | Oracle findings A/B and a gate check, 16 Oct | INPUT (open) | created 2026-10-16T17:47Z | `gh issue list` 2026-10-17: both OPEN |
| CI runs on master, 16 Oct | 38942843440 (`swiftright-ci`), 38942843234 (`swift-host-tests`) on `b0927b27e`; 38916701641 (hover N=20); 38916914529, 38916920414 (transactions); 38913551485 (H19 probe) | green evidence | COMPLETE | `gh run list` 2026-10-17 | all `completed success` |
| Local-build grant | commit `83056d3c6` | authorises D2 | COMPLETE | `83056d3c6` | `git log` 2026-10-17 |
| Continuity context + receipt | `tasks/handoffs/2026-10-16/720f96f5-...context.json` / `.context.receipt.json` | typed source evidence | COMPLETE | context sha256 `cb5100396a3a9cdebc86801f9470d788bde75f343c98280bfccb00942e6f7de7` | RECEIPT_PASS 2026-10-17 04:32 IST |
| Source scratch | `/Volumes/D/scratch/a8/res-{head,new,commit}.jsonl` | disposable result diffs from the source chat | COMPLETE, disposable | NOT_APPLICABLE: disposable scratch files | listed 2026-10-17 04:40 IST |

## 6. Failures, Dead Ends & Attempts

| ID | Attempt / command | Exact symptom / result | Cause / diagnosis | Evidence | DO_NOT_RETRY_UNLESS | Replacement / next diagnostic |
|---|---|---|---|---|---|---|
| FAILURE-01 | Hover cases on CI with host at HWND_BOTTOM + NOACTIVATE (run 38912970380) | real cursor reached every target but host printed no `HOST_EVENT kind=2`; in-B frame did not highlight | host left under other runner windows (inferred; z order not logged) | H25 in `docs/sr1-decisions.md` | z order before placement is logged and shows no covering window | CI-only HWND_TOPMOST placement (D10), passed N=20 run 38916701641 |
| FAILURE-02 | H19 flicker probe, PrintWindow vs screen BitBlt polling | 17 of 2432 PrintWindow polls show a black band; 0 screen polls black; grabs 37-173 ms apart | PrintWindow artifact likely; sub-gap on-screen transient not ruled out | run 38913551485, H19 | a continuous screen recording on a real desktop is requested | closed with limit (D13) |
| FAILURE-03 | Reporting agents as "running" without checking (16 Oct) | Adrian: "i dont see any action"; hover agent had died in a session restart with half-done uncommitted edits | session restart kills subagents | source chat events 1368-1377, 1516 | Adrian states a different rule in writing | check agent status before every report; after a restart, inventory and restart lanes |
| FAILURE-04 | `legion script handoff/transcript-handoff bootstrap --session-id aac102e0-...` (runtime session id) | `FAIL: no transcript matches platform, session ID, & workspace` | Claude Code transcript file UUID differs from the runtime task id | source events 1602-1606 | Adrian states a different rule in writing | pass the transcript filename UUID from `~/.claude/projects/-Volumes-D-claude-swiftright/` |
| FAILURE-05 | `ime-composing-v1` in CI run 38865487951 | 1 of 39 failed | fixed 10 s host lease (H22), not the change | decisions H22 and H23 in `docs/sr1-decisions.md` | the lease flag regresses in a capture host | lease flag honoured by 87 hosts; passes N=20 run 38870003524 |
| FAILURE-06 | Pushing all evidence to GitHub (13 Oct) | GitHub rejects files over 100 MB | large capture binaries | source event 22 | Adrian states a different rule in writing | keep files over 50 MB out of git (D14) |
| FAILURE-07 | `mac-stage-test.py` on the Mac | blocked by the workspace hook | hook policy | `docs/sr1-status.md` tests paragraph | Adrian states a different rule in writing | run `swift test` directly on the internal-disk git archive |
| FAILURE-08 | Asking Adrian to provision Azure signing (14 Oct) | "i aint doing shit for Azure, you figure it out bud" | reserved to agents | source event 539-548 | Adrian states a different rule in writing | use the Dell's signed-in Azure CLI; Apple secrets already in the `release` env |
| FAILURE-09 | Block 7 toggle and block 13 textfield after F2 body-font rebaseline (`3cb231a98`, stage `fc4a39a89`, G70) | fresh N=3 captures fail by 1 px | body font metric change | `docs/sr1-status.md` rows 7, 13 | a HEAD stage with the G70 baseline exists | re-deliver on HEAD with the G70 baseline; needs a fix or a measured gate change via decision |

## 7. Learnings, Gotchas & Landmines

| Signal | Hidden trap / learning | Required safe behavior | Source |
|---|---|---|---|
| Any GUI run on the Dell | Adrian works on it; windows flashing or foregrounding breaks his work; GUI only via one-shot interactive scheduled tasks under `D:\Claude\desktop.lock` | use the minimised Windows Sandbox or GitHub runners; window-targeted input only; never activate | D3; original handover DELL RULES |
| Deleting on the Dell over SSH | SendToRecycleBin over SSH is permanent | move into `D:\Claude\swiftright\.work` instead | original handover |
| Running a fresh binary from `/Volumes/D` on the Mac | TCC privacy prompts hit Adrian | build with `--scratch-path` on the internal disk; never prompt Adrian | memory `no-tcc-prompts-from-volumes-d` |
| Windowed test sweeps on the Mac | Adrian is at the Mac | never run windowed tests unless he says it is free; CI Mac is the default | memory `no-mac-gui-while-adrian-works` |
| Any Rust/Cargo command | ownership policy | `rightkit cargo` / `rightkit remote windows cargo`, one root build at a time, read `docs/rules/rightkit.md` first | workspace rules |
| `timeout` on the Mac | command not found (no coreutils) | wrap waits in Python or `win` directly | this turn |
| CI Mac scrollers | pinned to legacy; the H21 gutter rule applies only when a List overflows under legacy scrollers | overlay-scroller behaviour is unproven; do not claim it | decision H24 in `docs/sr1-decisions.md` |
| Windows overflowing List | clips with no scroll bar drawn | known gap, not a block failure | decision H24 in `docs/sr1-decisions.md` |
| Windows Sandbox | software rendering only; no timing tests; one Sandbox per host; a case takes ~6.5 min; occasionally exits and needs restart (comes back minimised) | timing/perf work needs the real Dell via scheduled task; rerun infra failures (timeout-client, exit -15) | source event 977 |
| `docs/proven-controls.json` | generated; edit `factory/tools/proven-controls/generate.py` (REVIEWED/OVERRIDES), then regenerate | never hand-edit the JSON | decision H26 in `docs/sr1-decisions.md` |
| Stage-bound verdicts | blocks 1-20 milestone is proven on stage `6459bb8cd-d243b1c9` only, not at HEAD | say "on stage X", never "at HEAD" without a HEAD run | Oracle 15 Oct |
| Hub-track doc | `docs/hub-track.md` dated 14 Oct says deliverables "in progress"; gaps were closed later | trust `docs/pulse-hub-windows-port.md` round 5/6 sections over the table | this turn |
| Commit messages and content | `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` trailer; repo is PUBLIC | no secrets, no private facts, explicit paths only | D14, system reminder |
| Adrian's cadence | he asks "status?", "we good?", "are you dead or alive?" when nothing visible happens | report checked facts only, end with Next:, never claim agents are running without checking | failures F3 and decision D5 in this packet |
| GitHub issues in this repo | track Adrian's requests as GitHub issues in this repo; check open issues every turn; close only with evidence | `/Volumes/D/claude/docs/rules/issue-workflow.md` | workspace rules |

## 8. Open Loops & Context Gaps

| Gap / open loop | Severity | Impact | Recovery action | Safe subset | Owner |
|---|---|---|---|---|---|
| Next lane not named by the source chat (it ended at "write the handoff") | MEDIUM | receiver must choose ordering among issues #2/#3, pending reviews, not-delivered blocks | follow §1 Current objective order (a)-(e); escalate ordering to Astra only if a material tradeoff appears | all of §10 | receiver |
| W08 long-run lock state in the Sandbox (`C:\sbq\state\longrun-active.json`) unverified this turn | MEDIUM | a new w08 job would be refused or would break the long run | `win "type C:\sbq\state\longrun-active.json"` equivalent via the Sandbox worker before any w08 job; use `--break-long-run` only after recording the long-run outcome | all non-W08 work | receiver |
| `docs/proven-controls.json` `statusDate` 2026-10-15 while rows carry 16 Oct reviews | LOW | consumers may think the registry is a day stale | regenerate via `generate.py` after the next status change | all SR1 work | receiver (Alchemist) |
| Block 27 narrowing lifted without Oracle re-review (D15) | LOW | registry row carries an unreviewed lift | include in the next Oracle review batch | all SR1 work | receiver |
| Pulse Swift's current asks | LOW | hub track may have new gaps since 16 Oct | read the Pulse Swift inbox/message on first contact; do not invent asks | all SR1 and SR0 work | receiver |
| SR0 freeze reserved to Adrian (D7, D8) | LOW | freeze cannot be declared by agents | present W08 proof + tuple 12 evidence when complete; do not ask repeatedly | everything except declaring the freeze | Adrian (reserved decision) |

## 9. Safety, Authority & Boundaries

- **May do:** edit runtime/bridge/host/factory code and docs in this checkout on `master`; run local iterative builds and unit tests (D2); dispatch `legion:alchemist` (Haiku) for mechanical work and `legion:alchemist-specialist` (Sonnet) for runtime semantics, concurrency, signing-adjacent or OS-framework work; dispatch `legion:oracle` (Opus) for reviews; run CI workflows via push or `gh workflow run`; commit by explicit path and push to `origin/master`; create/close GitHub issues; message Pulse Swift and other peer sessions; log Astra-approved decisions in `/Volumes/D/claude/decisions.md`.
- **Do not change:** LOCKED decisions D1-D14; `docs/proven-controls.json` by hand; `.github/workflows/release-candidate.yml` signing lanes without reading `docs/rules/release-signing.md`; ownership policy for Rust builds; Dell placement for hover (D10).
- **Do not run:** `git add -A`; any windowed/foreground run on the Mac or Dell desktop; `mac-stage-test.py` (hook-blocked); browser/Azure logins; cargo outside `rightkit`; deletes over SSH on the Dell; cold or non-dev builds.
- **Irreversible / production actions:** publication of packages, uploads to GitHub Releases/R2, deleting evidence, and the SR0 freeze need Adrian's explicit word; unsigned/test artifacts are never uploaded.
- **Spend / external effects:** GitHub Actions minutes on a public repo are in use and accepted; SendMessage to peer sessions is allowed; no paid compute beyond CI without reading `docs/rules/paid-compute.md`.
- **Secrets handling:** names only (§3); never print, echo or inspect values; Azure via the Dell's existing CLI session.
- **Reserved decisions:** W08 guard acceptance vs upstream (D7); freeze (D8); Narrator listening; ABI 0.7+ additive policy changes beyond what `docs/sr1-decisions.md` already records; destruction, spend, publication.

## 10. Exact Resume Sequence

### Resume Step 1 — Verify live repository and CI state

- **Owner:** receiver (Legion lead)
- **Working directory / system:** `/Volumes/D/claude/swiftright`
- **Exact action:**

```text
git fetch -q && git log --oneline -1 && git rev-list --left-right --count origin/master...master && git status --short | grep -v '^??' | wc -l && git status --short | grep -c '^??' && gh issue list -R Orthic-Labs/swiftright --state open && gh run list -R Orthic-Labs/swiftright --limit 3
```
- **Expected result:** HEAD `b0927b27e`; `0	0`; `0` modified tracked files; `366` untracked; issues #2 and #3 open; latest runs `completed success` on `b0927b27e`.
- **Evidence path:** `/Volumes/D/scratch/a6/resume-step1.txt` (tee the command output there)
- **Timeout / retry:** 60 seconds; retry once
- **If failure:** if HEAD moved or ahead/behind is non-zero, read `git log origin/master -5` and `docs/sr1-status.md` tail before anything else and treat §2 as stale; if an issue is closed, read its closing comment.
- **Depends on:** None checked.

### Resume Step 2 — Act on open issues #2 and #3

- **Owner:** receiver; #3 inline or `legion:alchemist` (Haiku); #2 `legion:alchemist-specialist` (Sonnet, reason: spec-bound SwiftUI completion/transaction semantics, a wrong fix still compiles)
- **Working directory / system:** `/Volumes/D/claude/swiftright`
- **Exact action:**

```text
gh issue list -R Orthic-Labs/swiftright --state open && gh issue view 3 -R Orthic-Labs/swiftright && gh issue view 2 -R Orthic-Labs/swiftright && sed -n 1900,1940p probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime/Graph.swift
```
- **Expected result:** #3: a decision whether `ime-recompose-v1` legitimately skips its pixel gate (record in `docs/sr1-decisions.md`, close with evidence). #2: a bounded runtime change making completions run after the enclosing transaction closes, with unit tests in `TransactionBoundaryScopeTests.swift`, then the 39-case N=3 regression and block 41 N=20 in CI.
- **Evidence path:** issue comments; `docs/sr1-decisions.md` new H-entry; CI run ids; `factory/pipeline/consolidation/results.jsonl`
- **Timeout / retry:** 120 minutes per issue; one Alchemist attempt, then one specialist attempt
- **If failure:** leave the issue open with the failing evidence linked; do not alter decision D9 without an N=20 real-SwiftUI measurement.
- **Depends on:** Resume Step 1 live-state verification.

### Resume Step 3 — Independent review of pending blocks

- **Owner:** `legion:oracle` (Opus), dispatched by receiver with `fork_turns: "none"`
- **Working directory / system:** `/Volumes/D/claude/swiftright` read-only
- **Exact action:**

```text
Dispatch legion:oracle: review blocks 39 swiftui.uia-walk (H24, runs 38854967920, 38872207896), 40 swiftui.ime-traps (run 38870003524 and its block rows), foundations.image-layout (10/10 at N=20, negative controls), and the block 27 narrowing lift (D15). Read docs/sr1-status.md, docs/sr1-decisions.md, docs/proven-controls.json, the cited CI runs via gh. No edits, no reruns. Return PASS / PASS-WITH-CAVEATS / BLOCK per block with findings.
```
- **Expected result:** verdicts recorded by `legion:alchemist` in `generate.py` REVIEWED, `docs/sr1-status.md`, `docs/sr1-decisions.md` (next H number), registry regenerated with today's `statusDate`, committed by explicit path, pushed, CI green.
- **Evidence path:** new commit on `master`; `docs/proven-controls.json` rows
- **Timeout / retry:** 45 minutes; retry once on tool failure
- **If failure:** a BLOCK finding keeps the block `delivered-pending-review`; open a GitHub issue per blocking finding with the evidence; continue with Step 4.
- **Depends on:** Resume Step 1 live-state verification; runs in parallel with Resume Step 2.

### Resume Step 4 — Re-deliver the not-delivered blocks

- **Owner:** `legion:alchemist` per block; specialist after one failed attempt
- **Working directory / system:** `/Volumes/D/claude/swiftright`; captures in CI (`factory-pairs.yml`) or the Dell Sandbox
- **Exact action:**

```text
For blocks 7 swiftui.toggle, 13 swiftui.textfield, 20 swiftui.color-scheme, 28 swiftui.system-font, 34 swiftui.textfield-axis: read the block row in docs/sr1-status.md and its FACTS.md, reproduce the failing delta on one case locally (D2), fix or propose a measured gate decision, then N=20 in CI, then Oracle.
```
- **Expected result:** each block `delivered` or `delivered-with-caveats` with review recorded.
- **Evidence path:** CI run ids in `results.jsonl`; `docs/sr1-status.md` rows
- **Timeout / retry:** 180 minutes per block lane; retry once after a named infrastructure failure
- **If failure:** record the exact delta and stage in the block row; leave `not-delivered`; never lower a tolerance without a decision entry.
- **Depends on:** Resume Step 3 verdicts for blocks 7 and 13 (shared body-font baseline G70).

## 11. State Verification & Invalidation

- **Verification command:**

```text
cd /Volumes/D/claude/swiftright && git rev-parse --short=9 HEAD && git rev-list --left-right --count origin/master...master && git status --short | grep -vc '^??' ; gh issue list -R Orthic-Labs/swiftright --state open --json number -q '.[].number' | tr '\n' ' '
```
- **Expected state:** `b0927b27e`; `0	0`; `0`; `3 2`
- **Invalidated by:** any new commit on `origin/master`; a closed or new issue; a new peer-session message about SwiftRight; a Sandbox long-run completion; Adrian's acceptance of W08 or a freeze instruction.
- **Refresh action:** `git fetch && git log origin/master -10 --oneline`, re-read `docs/sr1-status.md` headings and `docs/sr1-decisions.md` tail, `gh issue list`, then re-derive §2.
- **Validator command:**

```text
legion script handoff/validate-handoff /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.md --write-receipt /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.receipt.json
```

- **Receiver receipt check:**

```text
legion script handoff/validate-handoff /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.md --verify-receipt /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.receipt.json
```

## 12. First Output & Readback Contract

```text
READBACK
MISSION: <exact>
CURRENT_STATE: <exact>
LOCKED_DECISIONS: <list>
SAFETY_BOUNDARIES: <list>
NEXT_ACTION: <exact>
CRITICAL_GAPS: <none | list>
ASSUMPTIONS: <none | list>
FIRST_VERIFICATION: <exact>
PACKET_RECEIPT: <verified sha256>
```

- **First deliverable after readback:** Resume Step 1 output, then Steps 2 and 3 started in parallel, with a "Next:" line.
- **Gap report format:** `GAP: <severity> | <missing> | <impact> | <recovery> | <safe subset> | <owner>`

## 13. Ready-to-Paste First Message

```text
You are receiving a cold-start handoff with zero prior memory.
Treat only this packet plus its verified artifacts as context.
Verify packet receipt, return READBACK exactly as specified, correct any mismatch from packet, then follow Proceed mode.
Do not infer missing context, reopen LOCKED decisions, expose secrets, overwrite unrelated work, or execute reserved actions.
BEGIN HANDOFF PACKET AT: /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.md
RECEIPT AT: /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-16/swiftright-sr0-sr1-lead-20261016.receipt.json
```

## 14. Context Gap Report

- **Gap summary:** 0 FATAL, 0 HIGH, 2 MEDIUM, 4 LOW (§8)
- **Safe-to-proceed scope:** full §10 sequence; any W08 Sandbox job only after the long-run lock check (§8 row 2)
- **Fatal recovery owner:** NOT_APPLICABLE: no fatal gap
- **Exact recovery sequence:** NOT_APPLICABLE: no fatal gap; MEDIUM gaps recover inside Steps 1-2

## 15. Handoff Author Gate

- [x] Original user intent + active goal are exact, not paraphrased away.
- [x] Source evidence mode is explicit; Legion context path + prefix receipt are bound.
- [x] Live state was re-read from workspace/tools this turn.
- [x] Completed/in-progress/blocked/not-started states are separated.
- [x] Branch/version/dirty state or non-code equivalent is exact.
- [x] Active agents/processes/scheduled work were inventoried.
- [x] Decisions include rationale + reopen conditions.
- [x] Artifacts include locations + validation freshness.
- [x] Failures include raw evidence + DO_NOT_RETRY_UNLESS.
- [x] User corrections, learnings, gotchas, naming locks, & do-not-touch zones are captured.
- [x] No secret values appear.
- [x] Every gap has severity, impact, recovery, safe subset, & owner.
- [x] Readiness matches gap severities.
- [x] Resume Step 1 is immediately executable.
- [x] State verification + invalidation rules are exact.
- [x] Readback detects mission/state/boundary/next-action mismatch.
- [x] Cold-chat simulation passed with no unseen-context dependency.
- [x] `legion script handoff/validate-handoff` PASS receipt matches exact packet bytes.
