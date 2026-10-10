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
| package | **ran-FAIL** | real stage on R5 final2: `receipts-offline-4` fails (W08 FAIL; `expected_checks` has 14 entries, runner requires 15), `receipts-network-2` fails (3 entries, W12 only); macOS: no run record exists; default dir `qualification/receipts/package/` does not exist | see D4 |

Not runner stages and not covered: R6 itself (`F1MacRecord.app` re-record F1-F9, 100-run F6 sample) and any Windows-to-Mac compare for F2-F9 (the compare stage is F1 only).

## Defects found

| # | Defect | State |
|---|---|---|
| D1 | `SMOKE_BASE` was `D:\Claude\sr0b-abi0`, which does not exist on the Dell (also the `schedule-smoke.ps1` default); a real smoke stage could not start | **fixed**: base `D:\Claude\sr0b-abi06c`, plan passes `-Base` |
| D2 | `BUILD_ROOT` and `OUT_ROOT` were fixed under `/Volumes/D`: fresh Mac binaries would build and run there (removable-volume prompts) | **fixed**: env `SR0A_BUILD_ROOT`, `SR0A_OUT_ROOT` (defaults unchanged) |
| D3 | `compare` after `win-replay` needs `win-matrix/win-trace-v0.json`; nothing writes it, so that order can never pass | **fixed in the working tree (not committed)**: `win-replay` records the F1 schema-v0 trace when `compare` is in the run (see "Follow-up"); Dell-side recorder tree absent, so not run end to end |
| D4 | `package` needs one run record with all 15 W checks (and 12 M checks). R5 now emits two profiles (offline 14, network 3), so no R5 record can pass even without W08. No macOS record exists: `mac-clean-run.sh` never ran (refuses uid 501, M11 manual), R3 final and R7 evidence is not in the v2 receipt form | **runner side fixed**: profiles are evaluated as a union, W08 stays FAIL; macOS record still missing (section "macOS package record") |
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

No macOS run record exists, and `mac-clean-run.sh` cannot produce a passing one as written. What a passing record needs, in order:

**Where.** Inside a Tart clone of `sliceapp-base` (macOS 26.6.2 arm64, `tart run --no-graphics`, no `--dir` shares, SSH `admin@$(tart ip <clone>)` with `/Volumes/D/tart-home/keys/vmkey`; Gatekeeper already set to "App Store & Known Developers" per `examples/SliceApp/RESULT-R7.md`). Never on the Mac host: the harness writes `~/Downloads`, `~/Applications`, `~/Library/Application Support/SliceApp`, mounts DMGs and starts the app. Copy the repo's `qualification/clean-machine/mac-clean-run.sh` and the two DMGs into the guest, create `~/clean-machine-allow.txt` listing `admin` there (guest-side, mode 600). Delete the clone afterwards.

**Why it refuses uid 501.** `mac-clean-run.sh:36-37,85-86` refuse the main workspace user by name (`adrdsouza`) and by uid (`MAIN_UID=501`), so a run can never touch Adrian's account. The uid test is a stand-in for the name test and does not transfer: macOS gives the first account on any install uid 501, and the Tart guest's `admin` is uid 501 (`RESULT-R7.md:33`; the guest log `/Volumes/D/sr0-artifacts/mac/r7/s3-first-launch-online.log:18` shows `launchctl asuser 501` for the guest console user `admin`; I did not start the VM to run `id` again). So the script cannot run in the VM unmodified.

**Minimal safe guard (proposed, NOT applied).** Keep every refusal (root, name `adrdsouza`, allow-list owned by the user, `HOME=/Users/<user>`, all writes under `$HOME`), and apply the uid-501 refusal only when the machine is not a virtual machine:

```sh
in_vm() { [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] && case "$(sysctl -n hw.model 2>/dev/null)" in VirtualMac*) true ;; *) false ;; esac; }
[ "$uid" -ne "$MAIN_UID" ] || in_vm || die "refusing to run as uid $MAIN_UID outside a VM (main workspace user)"
```

Observed on this host: `kern.hv_vmm_present: 0`, `hw.model: Mac18,5`, so the host still refuses uid 501. Guest values (`1`, `VirtualMac2,1`) are the expected Virtualization.framework values and are UNVERIFIED: run `sysctl -n kern.hv_vmm_present hw.model; id` once in a clone before adopting the guard. Risks of the change: (1) inside a VM uid 501 is no longer refused, so the only remaining protection against a mistaken run in the guest is that the guest holds nothing of Adrian's (no `--dir` shares, no host credentials, clone deleted after); (2) the marker can be forged only on purpose (`sysctl` is read-only for a non-root user); (3) a Mac that runs another VM guest on a main account would be allowed: the name check and allow-list stay as the second layer. Update `mac-clean-checklist.md` ("uid 501") with the change. Needs Adrian's or the lead's approval; do not loosen it earlier.

**What it must run.** `bash mac-clean-run.sh --allowlist ~/clean-machine-allow.txt --old-dmg <0.1.0 dmg> --old-sha sha256:b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4 --old-version 0.1.0 --new-dmg <0.1.1 dmg> --new-sha sha256:<seal value> --new-version 0.1.1`, then copy `~/clean-machine-receipts/<run id>/` out and run `python3 -I qualification/run.py run --stages package --package-receipts <windows run dirs> <mac run dirs>`.

**Evidence it consumes.**
- Old DMG: `/Volumes/D/sr0-artifacts/mac/r3-final/SliceApp_0.1.0_arm64.dmg`, sha256 `b976ac70…` from the seal (`examples/SliceApp/r3-final/release-manifest.json:67`, `r3-final-verify.txt:4`), version 0.1.0, commit `4496474`, `@rightkit/release` 0.2.144. Pass the seal hash on the command line; never hash the copy to get it (M01).
- New DMG 0.1.1: **does not exist on the final chain.** `/Volumes/D/sr0-artifacts/mac/0.1.1` is the R7 build from 0.2.139 (`c75155b4…`, history). Build and seal a 0.1.1 DMG on the same commit chain and 0.2.144 (as Windows did with `clean2`), then set `members.new_dmg` in `qualification/tuple-final.json` with its source line. Until then the tuple marks it PENDING and the package stage fails any macOS record that carries `new_dmg`.
- Guest facts the checks read: bundle id `dev.orthic.sliceapp`, data `~/Library/Application Support/SliceApp/rows.json` schema 1 (checklist open item: confirm the path against the shipped app).

**Gaps in the harness that make a pass impossible today (each a separate change, none made here).**
1. M08 is a placeholder that always fails. R7 has a working method: `examples/SliceApp/scripts/interrupt-mac-install.sh` plus `interrupt-mac-install-hook.mjs` (modes copy, swap, swap-term against the real `right-release install-app --recover`, with the host node binary copied into the guest). Implement M08 on it.
2. M11 is a manual check. Split the run into two profiles (the runner takes the union): `--profile automated` lists M00-M10; `--profile manual` writes a run directory whose `expected_checks` is `["M11-window-visible"]`, with `observations.manual "true"`, `observations.observer`, and `artifact_ids.evidence` = sha256 of `M11-window-visible.png` taken per `mac-clean-checklist.md` step 5. `HarnessDriftTests` must then compare the union of the profiles with `PACKAGE_CHECKS["macos-arm64"]`. Do not record M11 in both profiles with different results (that is a FAIL).
3. M03 calls `xcrun stapler validate`; the vanilla VM has no Xcode tools (`RESULT-R7.md`: "VM has no stapler"), so it fails there. Replace the stapler step by `syspolicy_check distribution` (present in the guest, DMG PASS in R7) or install the Command Line Tools in the base image; do not drop the ticket check.
4. M05 and the other launch checks run the binary directly. Over SSH that session has no window server; R7 launched through the guest console session (`launchctl asuser`, which needs root in the guest, so a sudo wrapper outside the harness). Settle the launch method before the first run: a not-alive app is a FAIL, never a false pass.
5. The user, VM and Gatekeeper state are Adrian-owned setup (RESULT-R7): do not change system settings from the harness.
