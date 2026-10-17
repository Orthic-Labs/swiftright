# COLD-START HANDOFF: SwiftRight SR0+SR1 lead, swiftright-a6 to SwiftRight chat greeting

## 0. Handoff Control

- **Handoff ID:** sr-lead-a6-to-greeting
- **Created:** 2026-10-17T10:44:19+0530
- **Source task / chat:** Claude session 49644702-cd60-4ca0-a22d-85e40dcb1213 ("swiftright-a6", SwiftRight SR0+SR1 lead)
- **Target:** Claude session f9e8b610-7e2c-4d1e-ac13-40d17dd753b2 ("SwiftRight chat greeting")
- **Author:** SwiftRight chat greeting (target chat, TRANSCRIPT_INGEST)
- **Receiver role:** continuation (repository lead and integration owner for Orthic-Labs/swiftright)
- **Proceed mode:** IMMEDIATE
- **Readiness:** READY
- **Handoff reason:** Adrian's words in the source chat: "another swiftright chat will say hi to you, please give it a handoff to take over form you"
- **Source evidence mode:** TRANSCRIPT_INGEST
- **Transcript evidence path:** /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/49644702-cd60-4ca0-a22d-85e40dcb1213.context.json
- **Source prefix receipt:** PLATFORM:claude SESSION_ID:49644702-cd60-4ca0-a22d-85e40dcb1213 CUTOFF_BYTES:8982179 SHA256:6e7634ef414a5ce17aac6ea9bbf620f44d2fd582eafff4ca84ca4291cf8b80cf PARSER_VERSION:legion.transcript-event.v1
- **Packet path:** /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.md
- **Receipt path:** /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.receipt.json

## 1. Intent & Mission

- **Original user intent verbatim:** "another swiftright chat will say hi to you, please give it a handoff to take over form you" (to the source chat); to this chat: "do you see another swiftright chat? say hi to it". Standing intent from the source chat: close the open SwiftRight issues with evidence; Adrian, on the Tart VM: "i just want to run other work there, unrelated to swift, you can carry on with your work".
- **Underlying goal:** SwiftRight SR0 (runtime/renderer qualification, tuple 12, W08) and SR1 (SwiftUI block parity Mac vs Windows) closed with evidence; every open issue in Orthic-Labs/swiftright closed only with evidence.
- **Current objective:** finish the in-flight work: #30 compat rerun, #13 pilot-host port and rerun, apply Sage's tuple 12 adjudication to the docs, then run the build-only tuple 12 stage on the Dell (#17/#18).
- **Definition of success:** #30 closed on a passing 5-case compat rerun (CI run 39005378090); #13 closed when the 13 pilot-delivery-five-v1 cases pass at HEAD in CI (other 115 of 128 already passed in run 38995318951); Sage decisions recorded in the docs; #17/#18 closed with stage receipts; issues needing Adrian kept labelled needs-adrian.
- **Out of scope:** Tart VM `sliceapp-view` (Adrian's, unrelated work); resuming the Windows cross recordings (paused on Adrian's order); accepting W08 (#19, Adrian); ABI 0.6 freeze (#22, Adrian); Narrator (#23, Adrian); release publication.
- **First responsibility:** verify live state (git, CI run 39005378090, the 17 uncommitted pilot-port files).
- **Must not do first:** commit the pilot-port working-tree edits before reviewing them; touch `sliceapp-view`; run any Dell stage command before the Sage decisions are written into the docs.

## 2. Current State

- **Phase:** SR1 every block delivered or delivered-with-caveats (15 + 28 in docs/proven-controls.json); SR0 close-out and re-proofs in progress.
- **Completed:** block 28 delivered-with-caveats (7ed8d43ca, #7 closed); 39-case regression 39/39 on renderer-0.10-c13b62a4 (a0cd7f65b); blocks 1-20 re-proof 115/128 (f5f2b1626, run 38995318951); #30 measured (7987b926a) and fixed as H38 (49df66524, runtime 460/460 locally); #21 filed upstream as Orthic-Labs/rightkit#320.
- **In progress:** CI factory-pairs run 39005378090 (five block 41 compat cases at N=3 after H38), status `queued` at 2026-10-17T05:14Z; pilot-host port lane FINISHED (report relayed by swiftright-a6): 17 files modified, uncommitted and unbuilt, plus untracked factory/pipeline/ci-lists/pilot-13.txt; Windows hosts ported to the blocks-6-10 render-scale pattern (factoryRenderScale 2.5, HOST_SCALE_GUARD, bridge.run renderScale); three observe-mode Mac CaptureHost.swift files derive the scratch prefix from SWIFTRIGHT_CACHE_ROOT with NSHomeDirectory fallback; bundled-font-readiness-v6-line-limit-host pair.json gained macArgs --font-resource factory/resources/fonts/Tinos-Regular.ttf (SHA 60a0e8ef matches pin; licence SIL OFL 1.1). Open: Windows body font still resolved from window DPI (NativeWindowsBodyFontResolver.resolve(dpi: metrics.dpi), ~line 89; blocks-6-10 use scale*96) and resize path uses DPI logical width (~line 149).
- **Blocked:** #19, #22, #23, #28 need Adrian; #20 needs Adrian's word to resume cross recordings; #21 blocked upstream (rightkit#320).
- **Not started:** SR0 doc corrections from Sage (sage-tuple12-adjudication.md section 3) and the decision record in docs/sr1-decisions.md; build-only tuple 12 stage on the Dell; #15 H19 flicker probe; #16 H21 overlay-scroller measurement; #24 IME held patch; #25 selection highlight.
- **Last action:** source chat pushed H38 (49df66524) and dispatched run 39005378090; then emitted this handoff pointer.
- **Last observed result:** HEAD 49df66524 = origin/master; 14 open issues all labelled.
- **Active goal / plan:** compat rerun → close #30; review + CI the pilot port → close #13; apply Sage → Dell stage → #17/#18.
- **Current hypothesis:** the 13 pilot failures are lane incompatibility of the old pilot hosts (no Windows PNG, four Mac job failures), not a product regression.

## 3. Environment & Active Work

- **Work type:** MIXED
- **Workspace / repo:** /Volumes/D/claude/swiftright, GitHub Orthic-Labs/swiftright (PUBLIC)
- **Branch / version:** master
- **Baseline revision:** 49df66524dde7d5c40d1ad9d0fc533b056ed8d1f
- **Dirty state:** `git status --short`: 13+ modified main.swift files under factory/pipeline/pilot-delivery-five-v1/ (17 files, 121+/29- at 05:14Z) from the pilot-port lane; untracked factory/pipeline/ci-lists/pilot-13.txt, tasks/handoffs/2026-10-17/; untracked pre-existing: factory/pipeline/blocks-w1-i2/fit-raw.json, factory/pipeline/blocks-w1-i2/shared-mac-host/, factory/pipeline/ci-case-lists.json, factory/tools/sandbox/sandbox-cmd-20261015-010827/, probes/sr0-s/fresh-runtime/Tests/SwiftRightRuntimeTests/ZzObsTests.swift, qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/longrun/.cmd-out/
- **OS / shell:** macOS (Darwin 27.0.0), zsh; Dell Windows via `win "<cmd>"`
- **Tools / dependencies:** gh (account bogusyogi), swift test with --scratch-path under ~/Library/Caches/SwiftRightFactory/build, factory/tools/ci_fetch.py, factory/tools/proven-controls/generate.py, legion CLI
- **Services / processes:** Tart VM `sliceapp-view` running (Adrian's; IP 192.168.64.24)
- **Agents / tasks / threads:** none active; swiftright-a6 stopped acting on SwiftRight after relaying Sage and the lane report
- **Scheduled work:** none known
- **Credentials / access:** gh auth on Mac (bogusyogi); `win` SSH to the Dell; no values recorded

## 4. Decisions, Invariants & User Corrections

| ID | Decision / invariant / correction | Source / why | Status | Reopen only when |
|---|---|---|---|---|
| D1 tuple 12 stage identity | Canonical tuple 12 stage commit a9556b77f50315afcae27fc8fc44c0cd274959e2; EXE 87b8cb27 stays member; renderer 7578cd5d admitted under the lock-parse rule; scripts unedited, explicit -Commit/-RendererDll/-ExpectRenderer; SliceApp F73BE078 admitted; build-only stage proceeds now | Sage adjudication verbatim in /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sage-tuple12-adjudication.md | LOCKED | any reopen condition listed in that file occurs |
| D2 empty withAnimation H38 | an empty withAnimation/withTransaction body decides nothing | measured CI 39004758103; docs/sr1-decisions.md | LOCKED | compat rerun fails |
| D3 SR1 capture lane is CI | SR1 pixel captures run on CI factory-pairs.yml, not the Dell; Adrian's local-build grant covers quick iteration only | factory/pipeline/ci-case-lists.json runner note | LOCKED | Adrian changes it |
| D4 W08 and freeze holds | W08 must be fixed, not accepted; freeze held until W08 and tuple 12 close; 20 Mac + 20 Windows runs per config | Adrian's standing decisions recorded in docs/sr0-status.md | LOCKED | Adrian changes them in chat |
| D5 cross recordings paused | Windows cross recordings paused on Adrian's order | docs/sr0-status.md line 7 records the pause | LOCKED | Adrian says to resume them |
| D6 Tart VM is Adrian's | `sliceapp-view` belongs to Adrian for unrelated work | Adrian verbatim in section 1 | LOCKED | Adrian hands it back |

## 5. Artifacts & Evidence

| Artifact | Path / URL | Role | State | Version / hash | Validation + last checked |
|---|---|---|---|---|---|
| Status docs | docs/sr1-status.md, docs/sr0-status.md, docs/sr1-decisions.md, PENDING.md | authoritative state | COMPLETE | HEAD 49df66524 | read 2026-10-17 |
| Registry | docs/proven-controls.json (generated by factory/tools/proven-controls/generate.py) | block status | COMPLETE | 15 delivered, 28 with caveats | source chat 2026-10-17 |
| Results ledger | factory/pipeline/consolidation/results.jsonl | CI case rows | COMPLETE | as committed at 49df66524 | source chat |
| Blocks 1-20 list | factory/pipeline/ci-lists/blocks-1-20-closure.txt | input list for issue 13 re-proof | COMPLETE | commit 6c72ec646 | 128 cases, all directories present |
| Pilot list | factory/pipeline/ci-lists/pilot-13.txt | input list for the 13-case pilot rerun of issue 13 | DRAFT, uncommitted lane output | untracked file | lane checked each path has mac-source and package |
| Tuple 12 docs | docs/sr0-tuple12-staging.md, docs/sr0-tuple12-startupguard-staging.md, docs/sr0-tuple12-takeover-ledger.md, docs/sr0-tuple12-qualification.md | SR0 stage | INPUT, line corrections pending | as committed at 49df66524 | Sage section 3 lists the line corrections still to apply |
| Recovered renderer | probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/recovered-artifacts-r3/swiftright_render.dll | admitted tuple 12 renderer for issue 18 | COMPLETE | sha256 7578cd5d…, 11,887,616 B; Dell copy identical | verified by swiftright-a6 over SSH 2026-10-17 |

## 6. Failures, Dead Ends & Attempts

| ID | Attempt / command | Exact symptom / result | Cause / diagnosis | Evidence | DO_NOT_RETRY_UNLESS | Replacement / next diagnostic |
|---|---|---|---|---|---|---|
| F1 pilot cases fail in CI | blocks 1-20 re-proof run 38995318951 | 13 pilot-delivery-five-v1 cases fail: Windows PNGs 320x240 rejected by pair.py:294 size check; four Mac jobs failed (Tinos not found; hard-coded /Users/adrdsouza scratch prefix, NSCocoaErrorDomain 513) | hosts never ran on factory-pairs.yml before; scale 1.0 on runner | f5f2b1626 runs dirs | the port edits are reviewed and committed | decide body-font DPI point, run pilot-13 list at N=3 |
| F2 sizes-v1 network failure | block 28 sizes-v1 run 38994003228 | git fetch "Could not resolve host: github.com" | GitHub runner network | GitHub Actions log of run 38994003228 | the runner network failure recurs only by chance; rerun once | reran as 38995241565, 20/20 pass |
| F3 wrong tuple 12 stage pin | Staging tuple 12 at 0e201571 or db08e1a1 | cannot reproduce EXE pin 87b8cb27 | neither commit contains the built source (StartupGuard 05f2f684) | sage-tuple12-adjudication.md | a Sage reopen condition fires | stage at a9556b77f per D1 |
| F4 F7 r11 cross timeout | F7 r11 cross recording | "release_and_compose waitFor timed out" three times | undiagnosed | issue 20 comment of 2026-10-17 | the failure is diagnosed and Adrian resumes crosses | diagnose only after Adrian resumes crosses |

## 7. Learnings, Gotchas & Landmines

| Signal | Hidden trap / learning | Required safe behavior | Source |
|---|---|---|---|
| subagent builds | hook blocks subagent builds; only the owner chat runs swift test / CI | dispatch edit-only lanes; lead builds | source chat practice, AGENTS.md |
| documented resume/audit scripts | resume-tuple.ps1 / audit-tuple.ps1 default to historical renderer hash C62B554B and omit renderer params | pass explicit -RendererDll/-ExpectRenderer | Sage B3 prompt |
| Dell override drift | two Dell scripts in .work\sr0-stage-tools differ from transfer-manifest-r2.json (verify-artifacts.ps1, verify-manifest.ps1) | copy the a9556b77f versions and re-verify against transfer-manifest-r2.json before staging | swiftright-a6 Dell check in sage-tuple12-adjudication.md |
| Windows signing cert | expired 2026-10-12 | no signed Windows builds | Sage prompt |
| Mac windowed test sweeps | no windowed sweeps on the Mac while Adrian works | use CI or Tart clones of sliceapp-base | user memory file no-mac-gui-while-adrian-works.md |
| run output | write run output only under /Volumes/D/scratch | source chat used /Volumes/D/scratch/a6 | AGENTS.md |

## 8. Open Loops & Context Gaps

| Gap / open loop | Severity | Impact | Recovery action | Safe subset | Owner |
|---|---|---|---|---|---|
| Windows pilot body font resolved from window DPI, not scale*96 | MEDIUM | pilot text may render at wrong size on the runner | decide per blocks-6-10 pattern before committing the port | everything except committing the pilot port | receiver lead |
| `pulse` not on Mac PATH, so Adrian's pause wording is unquoted | MEDIUM | Dell GUI runs (smoke, pixels, R9, R10) cannot start | ask Adrian or find pulse; no GUI run until quoted | doc corrections and build-only stage | receiver lead |
| 4143 unsupported rows and 190 reasoning rows omitted by the parser | LOW | older history absent from context | docs, issues and results.jsonl hold durable state | all work in this packet | receiver lead |

## 9. Safety, Authority & Boundaries

- **May do:** commit and push to Orthic-Labs/swiftright master; dispatch CI factory-pairs runs; read/close issues with evidence; read-only and stage commands on the Dell once docs are corrected; dispatch Alchemist/Oracle/Sage lanes.
- **Do not change:** `sliceapp-view`, `sliceapp-base`, `sliceapp-clean-pristine` images; LOCKED decisions D2-D6.
- **Do not run:** Windows cross recordings; W08 acceptance; signed Windows release work; Mac windowed sweeps.
- **Irreversible / production actions:** no releases or publication without Adrian naming the build.
- **Spend / external effects:** public repo CI is free; no paid compute.
- **Secrets handling:** names only; never print tokens.
- **Reserved decisions:** #19 W08 acceptance, #20 cross resume, #22 freeze, #23 Narrator, #28 Mac-free word.

## 10. Exact Resume Sequence

### Resume Step 1 — Verify live state

- **Owner:** receiver
- **Working directory / system:** /Volumes/D/claude/swiftright
- **Exact action:**

```text
git rev-parse HEAD origin/master; git status --short | grep -v '^??' | wc -l; gh run view 39005378090 -R Orthic-Labs/swiftright --json status,conclusion
```
- **Expected result:** HEAD = origin = 49df66524 (or later if the lead committed); run status reported
- **Evidence path:** /Volumes/D/claude/swiftright/.git/HEAD
- **Timeout / retry:** 2 minutes, 1 retry
- **If failure:** refresh the packet's state section before acting
- **Depends on:** packet receipt verified by validate-handoff

### Resume Step 2 — Close #30 on the compat rerun

- **Owner:** receiver
- **Working directory / system:** /Volumes/D/claude/swiftright
- **Exact action:**

```text
gh run watch 39005378090 -R Orthic-Labs/swiftright --exit-status (background); python3 factory/tools/ci_fetch.py 39005378090; commit run dirs + results.jsonl; gh issue close 30 with evidence
```
- **Expected result:** five cases pass at N=3
- **Evidence path:** factory/pipeline/consolidation/results.jsonl
- **Timeout / retry:** 60 minutes CI wall clock, 1 rerun on network failure
- **If failure:** diagnose the failing case against H38, fix in probes/sr0-s/fresh-runtime, rerun suite
- **Depends on:** Resume Step 1 showing HEAD 49df66524 or a known later commit

### Resume Step 3 — Review and run the pilot-host port (#13)

- **Owner:** receiver
- **Working directory / system:** /Volumes/D/claude/swiftright
- **Exact action:**

```text
git diff factory/pipeline/pilot-delivery-five-v1; commit after review; gh workflow run factory-pairs.yml -R Orthic-Labs/swiftright --ref master -f cases="<pilot-13 list>" -f runs=3
```
- **Expected result:** 13 cases pass; close #13 with runs 38995318951 + new run
- **Evidence path:** /Volumes/D/claude/swiftright/factory/pipeline/consolidation/results.jsonl
- **Timeout / retry:** 90 minutes CI wall clock, 1 rerun per failing case
- **If failure:** dispatch a fix lane per failing case
- **Depends on:** body-font DPI decision from section 8 made and the diff reviewed

## 11. State Verification & Invalidation

- **Verification command:**

```text
git -C /Volumes/D/claude/swiftright log -1 --format=%H; gh issue list -R Orthic-Labs/swiftright --state open --json number -q length
```
- **Expected state:** 49df66524dde7d5c40d1ad9d0fc533b056ed8d1f; 14
- **Invalidated by:** new commits by anyone else, a reply from swiftright-a6 contradicting D1, Adrian's new instructions
- **Refresh action:** re-read docs/sr0-status.md and docs/sr1-status.md and the issue list
- **Validator command:**

```text
legion script handoff/validate-handoff /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.md --write-receipt /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.receipt.json
```

- **Receiver receipt check:**

```text
legion script handoff/validate-handoff /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.md --verify-receipt /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.receipt.json
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

- **First deliverable after readback:** READBACK sent to swiftright-a6 and shown to Adrian, then Resume Step 1.
- **Gap report format:** `GAP: <severity> | <missing> | <impact> | <recovery> | <safe subset> | <owner>`

## 13. Ready-to-Paste First Message

```text
You are receiving a cold-start handoff with zero prior memory.
Treat only this packet plus its verified artifacts as context.
Verify packet receipt, return READBACK exactly as specified, correct any mismatch from packet, then follow Proceed mode.
Do not infer missing context, reopen LOCKED decisions, expose secrets, overwrite unrelated work, or execute reserved actions.
BEGIN HANDOFF PACKET AT: /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.md
RECEIPT AT: /Volumes/D/claude/swiftright/tasks/handoffs/2026-10-17/sr-lead-a6-to-greeting.receipt.json
```

## 14. Context Gap Report

- **Gap summary:** 0 HIGH, 2 MEDIUM, 1 LOW
- **Safe-to-proceed scope:** full scope except Dell GUI runs and the reserved decisions
- **Fatal recovery owner:** NOT_APPLICABLE: no FATAL gap
- **Exact recovery sequence:** NOT_APPLICABLE: Sage text and lane report received and saved; MEDIUM gaps handled in section 8

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
