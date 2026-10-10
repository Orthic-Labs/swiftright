# R8 partial: qualification runner on the final tuple

10 October 2026, repo HEAD `c370228`, Mac mini macOS 27.0.1 arm64. Run output: `qualification/out/r8-partial-final.txt` (`qualification/out/` is gitignored: `git add -f` it). No Mac GUI program was launched and no Dell desktop job was started. Dell access was read-only `win` queries.

Final tuple (`docs/sr0-snapshot.md` 2c): renderer `7533963D…3F149FC`, FreshOnBridge `AA4353CE…E1D7E`, BridgeSmoke `21992F16…DF1A5`. The three hashes were re-read on the Dell (`D:\Claude\sr0s-bridge06f`, `D:\Claude\sr0b-abi06c`) and equal the tuple.

## Stage table

| Stage | Status | What ran | What a no-skip run still needs |
|---|---|---|---|
| unit tests | ran-PASS | `python3 -I -m unittest discover -s qualification -p 'test_*.py'`: 74/74 OK, before and after the three edits below | nothing |
| mac-oracle | **blocked** (offline half ran-PASS) | `load_accepted` on all 16 configs: 16/16 baselines intact (canonical v2). `FixtureApp` builds from the HEAD fixtures tree `1b4affaf44f8` (sha256 `5b71cb56…aada3b7`), not launched. Baselines were seeded from tree `bb4258a2549f`; SR1 edits to `FixtureSession.swift` and `SelfTest.swift` landed since, so whether F1-F9 traces are unchanged is only known after a launch | Mac free: 16 configs x 3 launches, about 5 to 8 min incl. build. F6 is unstable under canonical v2 (1 of 20 runs), so a 3-run F6 fails about 14% of the time until the F10 decision |
| win-replay | **blocked** (ingestion ran-PASS) | `win_stage` fed the 320 committed `matrix-final` records: 320/320 PASS, ids exe `aa4353ce…`, renderer `7533963d…`, trace `84c2f00b…`. Separate audit: 320/320 records carry the ARTIFACT header and ARTIFACTS line with the final hashes | Dell desktop: about 13 s per run, 48 runs (16 x 3) about 11 min; 16 x 20 about 71 min (`matrix-final` timestamps) |
| compare | ran-PASS, **not final-tuple** | real runner stage, 0 diffs. Inputs are historical: Mac `accepted/F1/trace-v0.json` = `mac-trace-strict-m1.json` (9 Oct, `eaf40dc`, before the R6 signed-recorder re-record) and Windows `win-trace-strict-w6.json` (0.5 stack, exact binary UNVERIFIED per snapshot section 4) | R6 F1 re-record on the Mac, replace `accepted/F1/trace-v0.json` (no runner command does this), and a fresh Windows F1 trace on the final FreshOnBridge (Dell desktop: `schedule-f1.ps1 -Mode record -Bin D:\Claude\sr0s-bridge06f\scratch\out\Products\Release-windows-x86_64`, then `F1Assemble win`) |
| smoke | **blocked** (ingestion ran-PASS) | `smoke_stage` fed `result-smoke-rev06final.txt` (40/40) and `result-smoke-timeout06final.txt` (41/41): PASS, exe `21992f16…`, renderer `7533963d…` | Dell desktop, about 1 min. The runner dispatches the normal mode only, not timeout mode |
| package | **ran-FAIL** | real stage on R5 final2: `receipts-offline-4` fails (W08 FAIL; `expected_checks` has 14 entries, runner requires 15), `receipts-network-2` fails (3 entries, W12 only); macOS: no run record existed then (now recorded: section "macOS package record") | see D4 |

Not runner stages and not covered: R6 itself (`F1MacRecord.app` re-record F1-F9, 100-run F6 sample) and any Windows-to-Mac compare for F2-F9 (the compare stage is F1 only).

## Defects found

| # | Defect | State |
|---|---|---|
| D1 | `SMOKE_BASE` was `D:\Claude\sr0b-abi0`, which does not exist on the Dell (also the `schedule-smoke.ps1` default); a real smoke stage could not start | **fixed**: base `D:\Claude\sr0b-abi06c`, plan passes `-Base` |
| D2 | `BUILD_ROOT` and `OUT_ROOT` were fixed under `/Volumes/D`: fresh Mac binaries would build and run there (removable-volume prompts) | **fixed**: env `SR0A_BUILD_ROOT`, `SR0A_OUT_ROOT` (defaults unchanged) |
| D3 | `compare` after `win-replay` needs `win-matrix/win-trace-v0.json`; nothing writes it, so that order can never pass | **fixed in the working tree (not committed)**: `win-replay` records the F1 schema-v0 trace when `compare` is in the run (see "Follow-up"); Dell-side recorder tree absent, so not run end to end |
| D4 | `package` needs one run record with all 15 W checks (and 12 M checks). R5 now emits two profiles (offline 14, network 3), so no R5 record can pass even without W08. No macOS record exists: `mac-clean-run.sh` never ran (refuses uid 501, M11 manual), R3 final and R7 evidence is not in the v2 receipt form | **fixed**: profiles are evaluated as a union, W08 stays FAIL; the macOS record now exists and passes (section "macOS package record") |
| D5 | The runner records exe and renderer hashes but never checks them against the tuple: the old `rev06c` smoke receipt (renderer `777F14C4`) passes the smoke stage (negative control in the output file) | **fixed**: exe, renderer and package hashes are compared with `qualification/tuple-final.json`; the rev06c negative control now FAILs |
| D6 | `docs/qualification.md` line 137 says `schedule-fixture.ps1` and `drive-smoke.ps1` do not emit the ARTIFACTS line; both do (`drive-fixture.ps1:377`, `drive-smoke.ps1:219`, 320/320 matrix-final records). `win-replay` defaults to F1, F2 x 3 only: pass `--configs` for the full set | **fixed**: `docs/qualification.md` corrected; `win-replay` now defaults to the full 16 configs |

## Edits to `qualification/run.py` (not committed)

`git diff`: `OUT_ROOT`/`BUILD_ROOT` read the two env vars, `SMOKE_BASE` set to `D:\Claude\sr0b-abi06c`, `-Base {SMOKE_BASE}` added to the smoke command. +6/-4 lines, 74/74 tests still pass.

## Full run once R6 and a Dell desktop window exist

Superseded in part by the follow-up below: D3 is fixed in the working tree, so `compare` can follow `win-replay` in one invocation, and `--configs` defaults to the full 16. Both must exit 0. The Mac stages (`mac-oracle`, F1 re-record R6) still need a free Mac; the Dell stages need the desktop and the F1 recorder tree.

```
cd /Volumes/D/claude/swiftright
export SR0A_BUILD_ROOT=/private/tmp/sr0a-build SR0A_OUT_ROOT=/private/tmp/sr0a-out

python3 -I qualification/run.py run --stages mac-oracle win-replay compare smoke package \
  --runs 3 --win-runs 3 --confirm-windows-gui \
  --package-receipts <windows run dirs: offline and network> <mac run dirs: automated and manual>
```

The tuple (`qualification/tuple-final.json`) is applied by default; `--no-tuple` makes the run non-qualifying.

## Follow-up (HEAD `0cdc199`, working tree, not committed)

Changes: `qualification/run.py`, `qualification/test_run.py` (74 to 115 tests; one needs `SR0A_BUILD_ROOT`), `qualification/tuple-final.json` (new), `docs/qualification.md`. Details and rules: `docs/qualification.md`, section "2026-10-10 R8 follow-up". Re-run results: `qualification/out/r8-partial-final.txt`, heading "R8 follow-up".

- D3: `win-replay` runs the F1 record job (`verify-artifacts.ps1`, `schedule-f1.ps1 -Mode record`, file pulls, `F1Assemble win --keep-lists`) and writes `win-matrix/win-trace-v0.json`. The assemble half is verified: it reproduces the committed `win-trace-strict-w6.json` bit for bit from the committed W6 evidence. The Dell half is not: `D:\Claude\sr0o-f1` (scripts, `f1-steps-win.json`, `UIARecorder.exe`) no longer exists on the Dell (read-only `win` query), so the step fails fast naming it; rebuild with `probes/sr0-o/f1-cross/scripts/build-rec.ps1` before a full run. The R6 Mac re-record of `accepted/F1/trace-v0.json` is still PENDING, so a full `compare` is not final-tuple until then.
- D4: union of profiles. Which checks may be manual: only `M11-window-visible`, recorded as described in `docs/qualification.md`.
- D5: tuple file, default for `run`, `--no-tuple` = non-qualifying (skip events, exit 1). `new_dmg` is PENDING in the tuple (no 0.1.1 DMG on the final 0.2.144 chain exists).
- Smoke: normal 40/40 plus timeout 41/41 (`-SkipShutdown`), both pinned.
- D6: doc fixed; default `--configs` = all 16 (chosen deliberately: a default that passes 2 of 16 configs is a trap, and `mac-oracle` already defaults to all 16).

## macOS package record

State (10 Oct 2026, working tree on top of `0be0ea3`, not committed): `mac-clean-run.sh` now produces a passing, honest record inside a Tart clone. Real record: two fresh clones of `sliceapp-base` (macOS 26.6.2 25G83, arm64), old = R3 final 0.1.0 `b976ac70…`, new = R3 final 0.1.1 `75f3cd75…` (both seal values passed on the command line), harness sha256 `7e47eb88…`. Receipts: `qualification/receipts/package/mac-20261010T024420Z-automated/` (M00-M10, 11/11 PASS) and `mac-20261010T024653Z-window-server/` (M11, PASS). Guest logs and the package-stage output: `/Volumes/D/sr0-artifacts/mac/r8-record/`. Package stage with the R5 final2 Windows runs (`receipts-offline-4`, `receipts-network-2`) and both macOS runs, tuple-pinned: **macOS 12/12 PASS; Windows FAIL on W08 only**; exit 1 as expected. Clones deleted (`tart list`: only `sliceapp-base`, `sliceapp-clean-pristine`).

**Guest values (observed, probe clone, then again in both record clones).** `sysctl -n kern.hv_vmm_present` = `1`, `hw.model` = `VirtualMac2,1`, `id` = `uid=501(admin)`, `sw_vers` = macOS 26.6.2 (25G83), `spctl --status` = assessments enabled, `syspolicy_check` at `/usr/bin/syspolicy_check`, `xcrun` at `/usr/bin/xcrun` (a shim: no developer tools, each call pops an install dialog), `python3` is the same kind of shim, `perl` 5.34 (JSON::PP 4.06) and `osascript` are real, passwordless `sudo -n` works. Host: `0` and `Mac18,5`.

### Changes (all in the working tree)

| File | +/- | What |
|---|---|---|
| `qualification/clean-machine/mac-clean-run.sh` | +510/-187 (478 to 801 lines) | 1. VM guard: uid 501 refused only outside a VM (`in_vm` = `kern.hv_vmm_present` 1 and `hw.model` `VirtualMac*`); every other refusal kept (root, `adrdsouza`, allow-list ownership/mode/membership, `HOME`, paths under `$HOME`), receipts dir must be empty. Tested in the guest: uid 501 refused when `sysctl` is faked to a non-VM, allow-list without `admin` refused. 2. M08 on R7's interrupt method (below). 3. Profiles `automated` (M00-M10), `window-server` (M11, unattended), `manual` (M11, evidence file). 4. M03 without `xcrun`. 5. Launch (below). Also: JSON written with perl (the guest has no python3), seal hashes validated as `sha256:<64 hex>`, M02 `chmod u+w` (a sealed DMG is 0444 and `xattr -w` failed), M00 requires no default route (v4, v6, scoped) and an unreachable `apple.com`, M05 requires no pre-existing `rows.json`, M06 requires two different builds (`--allow-same-dmg` dry-run switch: M06 then FAILS honestly) |
| `qualification/clean-machine/mac-vm-offline.sh` | +33, new | removes the guest's default routes (R7's method); refuses outside a VM; outside the harness |
| `qualification/clean-machine/mac-clean-checklist.md` | +122/-54 | the guard, profiles, exact commands, per-check meaning, why M11 is not a screenshot |
| `qualification/test_run.py` | +77/-3 (115 to 119 tests) | `HarnessDriftTests`: automated + manual profiles equal `PACKAGE_CHECKS["macos-arm64"]`, window profile equals manual, guard text, no python3/xcrun/stapler in code, M08 three modes, and the harness's own perl writers run on synthetic input and loaded with the runner |
| `docs/qualification.md` | +2/-2 | M11 sentence and test count |

### Per check (real record)

| Check | Result | Evidence in the receipt |
|---|---|---|
| M00 | PASS | arm64, `default_routes` 0, `apple.com` probe HTTP code 000, `vm` true, `VirtualMac2,1` |
| M01 | PASS | both DMGs equal the seal values |
| M02 | PASS | both copies equal the seal, `0081;...;Safari;<uuid>` quarantine on each |
| M03 | PASS | old and new DMG and `.app` inside each: `spctl` source `Notarized Developer ID`, `syspolicy_check distribution` rc 0 (12 observations). `xcrun stapler validate` is gone. What it proves: spctl = Gatekeeper accepts the artifact as notarized; `syspolicy_check` = the ticket is stapled to that artifact (a missing staple is the fatal "Notary Ticket Missing") plus signature and hardened-runtime checks. Not proven: an `.app` delivered without its DMG |
| M04 | PASS | quarantined DMG mounted read-only, gate (codesign, spctl, version 0.1.0, bundle id), `ditto` |
| M05 | PASS | offline, no earlier `rows.json`, alive, window server lists 1 on-screen window 900x450 after 1 s, syspolicyd "GK eval" allowed 2 / denied 0, `rows.json` schema 1 |
| M06 | PASS | 0.1.1 installed, `rows.json` sha unchanged, new build alive with a window |
| M07 | PASS | one flipped byte (offset 112576, `a8` to `a9`), gate rc 1, installed binary sha unchanged |
| M08 | PASS | all three R7 modes, each rc 0, hook fired, 0 EXPECT FAIL: `copy` 8 pass (old 0.1.0 present and verifying after the kill), `swap` 6 pass (**app ABSENT right after the SIGKILL**, the known R7 window; restored by `--recover`), `swap-term` 9 pass (old present after the rollback); after `--recover` the installed app is the old bundle in all three. node v26.8.1, `@rightkit/release` 0.2.145 |
| M09 | PASS | 0.1.0 reinstalled, launched, reads the data 0.1.1 wrote (`rows.json` schema 1) |
| M10 | PASS | bundle moved to `uninstalled/`, `rows.json` sha unchanged |
| M11 | PASS (window-server profile) | see below |

### M08

R7's method unchanged: `examples/SliceApp/scripts/interrupt-mac-install.sh` and its hook against the real `right-release install-app --recover` (0.2.145 package and the host node binary copied into the guest, no patch), scratch destination under `~/clean-machine-work` (`TMPDIR` pointed there), old and new DMGs the quarantined, seal-checked copies. The harness runs `copy`, `swap` and `swap-term` (everything R7 proved on 0.2.142) and records per mode the exit code, hook-fired flag, EXPECT PASS/FAIL counts, the state after the interrupt and after recovery, and the log hash. A mode that does not fire its hook, or has any EXPECT FAIL, fails M08. 0.2.145's `install-app` takes the "no stapler on this host" path (`spctl-only` ticket) in the guest, as 0.2.142 did.

### M11: what I did and why

`screencapture` cannot work headless here: with `--no-graphics` and with `--vnc-experimental`, run through `launchctl asuser` as `admin`, it prints "could not create image from display"; `tccd` logs `kTCCServiceScreenCapture does not allow prompting; returning denied`. Screen Recording is a TCC grant, a system privacy setting the harness and agents must not change. So M11 is not an automated screenshot. Two profiles exist, both M11 only, and the runner must get exactly one (their evidence differs, so both fail the union rule):

- `window-server` (used for the record): install the old build on a fresh clone, launch it, and require the window server's list (CGWindowList through `osascript`) to hold an on-screen, alpha > 0, layer-0 window of at least 200x100 for the app process. Evidence = sha256 of the raw window-server dump (`M11-window-visible.windows.json`: one 900x450 window at 62,145). Observer `harness`, method stated in the receipt. **This is weaker than a screenshot** (it does not show the window renders correctly); it is not a manual observation and does not claim to be. The decision to accept it for M11, or to require a screenshot, is the lead's.
- `manual`: `--evidence <png> --observer <name> --note <text>`; `observations.manual "true"`. Mechanics dry-run only (synthetic PNG, labelled as such, not kept); no human or agent observation was made, so none is recorded.

### Launch method (item 5)

Direct exec of the installed binary from the SSH session, not `open` and not `launchctl asuser`, because `open` could not pass unattended: the `ditto` copy inherits the DMG's quarantine, so LaunchServices shows the first-open prompt and holds the process at 0 CPU. In dry run 1 this left an unanswered Gatekeeper evaluation for that install path, and every later launch from that path was held until killed (`syspolicyd`: "waiting on another evaluation"); hence one profile per fresh clone. Direct exec in this guest does reach the console session's window server (CGWindowList lists the app's window from the SSH session) and Gatekeeper still evaluates the quarantined exec offline (`GK eval - was allowed: 1, show prompt: 0`, counted per launch). An app that is not alive, or has no window within 60 s, is a FAIL (never a false pass). Not exercised: the LaunchServices first-open prompt (R7 final covered it by hand over VNC, 10/10).

### Dry-run findings that shaped the harness

No python3 in the guest (shim; each call pops an install dialog); `xcrun stapler` unusable; sealed DMGs are 0444; plain `ditto` from a quarantined DMG carries the quarantine; the `open` hold above. Same-DMG smoke (R3 final as both, `--allow-same-dmg`): 10 of 11 PASS, M06 FAIL by design.

### Open

- A human or agent screenshot for M11 (`--profile manual`) if the window-server evidence is not accepted: needs a Screen Recording grant (Adrian) or a VNC capture; run it against a window that is up, and pass the runner that profile instead of `window-server`.
- The user, VM and Gatekeeper state remain Adrian-owned setup (RESULT-R7); the harness changes none of them.
