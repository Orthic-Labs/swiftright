# W08 upstream handoff

W08 stays `FAIL` until `@rightkit/release` supplies one versioned repair path & fresh evidence. Installed `0.2.151` has no verified helper/remediation match; adopting it does not close W08.

Release owner must provide:

1. **Helper source & provenance** — helper/installer/feed implementation, exact upstream commit or package version, source archive hash, published package hash, supported Windows/runtime versions, & ownership of future fixes.
2. **Installer/feed integration** — final old/new MSIX pair, package identity/version, App Installer feed URL or local test host, manifest/update settings, signing receipt, certificate identity/timestamp, & explicit invocation from SliceApp update flow.
3. **Recovery contract** — documented command/API used after cancellation, expected exit codes, package-state transitions, idempotence, data/user-path preservation, relaunch behavior, & failure diagnostics. Manual Settings Repair or same-version redeploy alone is insufficient.
4. **Clean-machine evidence** — fresh VM/Sandbox run with update cancellation landing in `Modified, NeedsRemediation`; helper invocation must transition package to launchable state; capture before/after package state, old/new versions, app launch, persisted data, logs, & exact timestamps.
5. **Negative controls** — cancellation outside registration, helper on healthy package, wrong package identity, stale feed, corrupt package, & repeated helper invocation. Each must return expected nonzero/result state without data loss.
6. **Tuple12 binding** — receipts bind helper/source/package bytes to tuple12 source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`, renderer candidate `7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2`, & release metadata. Re-run package qualification after any changed byte.

Acceptance requires release owner review, exact receipt files & hashes, reproducible helper invocation, cancellation-state repair, relaunch, data-integrity proof, & package signature proof. Until then freeze stays held, approved 20-per-side comparison remains required, & Narrator listening remains later human follow-up.

## Tier 2 repair guard: Sandbox acceptance (2026-10-13)

Commits `71aa269e0` (guard), `8a92c9bd0` + `bff7c2a85` (fixes below). Guard = `packages/SwiftRightBridge/guard/repair-guard.ps1`, installed by `Bridge.run` on each packaged launch as per-user task `<PFN>-Repair` (event 751 + logon). Runs: long-lived minimised Windows Sandbox worker (`factory/tools/sandbox/client.py w08`, software rendering), test packages `.work/w08t2/pkgs-t4` (old sha256 `731F6B9A...956F`, new `85D2CDDD...3382`; sealed Tier 1 pair with a rebuilt `SliceApp.exe`, self-signed `CN=SwiftRight W08 Test`, tuple 12 renderer `954977...`). Not release-signed packages; the guard code path is the product's.

Defects found and fixed (both were the reason no recovery could ever be observed):
1. Packaged launch crashed (`0xc0000409`, ucrtbase, WER event 1000, FAST_FAIL) inside `RepairGuard.installIfNeeded`: Foundation `Process` with `FileHandle.nullDevice` stdio fast-fails in a packaged Windows launch. Proof: same package with `SWIFTRIGHT_REPAIR_GUARD=0` runs; unpackaged exe runs; guard on crashes right after writing `repair-guard.ps1`. Fix: `CreateProcessW` + `CREATE_NO_WINDOW`. Not a renderer problem (no change to render/ or the tuple 12 pins).
2. Guard repair mode never ran: `New-Object Threading.Mutex($false, ...)` bound the 4-argument form and threw before the first log line (the task action runs under `conhost --headless`, which hides the failure and exits 0). Fix: `[Threading.Mutex]::new`; also decode a `byte[]` feed body (`application/appinstaller`), and log any unhandled error (exit 4).
3. Harness: `Start-Feed` restart after the feed-down kill failed (stale http.sys sslcert bindings); now deletes them first.

Results (induced = `Modified, NeedsRemediation` with event 751; no action of ours, launch via `shell:AppsFolder`, package Ok, `rows.json` sha equal to the written marker sha, marker row shown in the UI):

| Run | Offset (ms after staging; cancel at) | Induced | Recovered | Seconds cancel to Ok | Launch OK | Data hash OK |
|---|---|---|---|---|---|---|
| r360-a | 360 (443) | yes | yes, 0.1.1.0 Ok | 12.5 | yes | yes |
| r360-b | 360 (430, 2nd attempt) | yes | yes | 12.7 | yes | yes |
| r400-a | 350 (407, 4th attempt) | yes | yes | 13 | yes | yes |
| r400-b | 400 (513) | yes | yes | 12.5 | yes | yes |
| feed-down fd-b | 350 (424) | yes | stays NeedsRemediation with feed down; repair.log `FAILED ... feed unreachable ... msix unreachable`; Ok 11.9 s after feed restored | n/a | yes | yes |
| feed-down fd-c | 350 (416, 8th attempt) | yes | same: explicit failure logged, Ok 13.1 s after feed restored | n/a | yes | yes |
| uninstall un-a / un-b | none | n/a | task and `%LOCALAPPDATA%\SliceApp\repair` removed 15.3 s after Remove-AppxPackage (task started as the logon stand-in); `rows.json` and parent folder kept | n/a | n/a | yes |

Not met as asked: offset 240 ms. In this Sandbox the cancel at 240 (actual 297-328 ms after the call) always lands in the Staged state handler and Windows rolls back cleanly (`old-ok`, 16/16 attempts over two runs; 300/320: 8/8 `old-ok`); NeedsRemediation needs the cancel at about 350-440 ms, where it is probabilistic (`completed-anyway` when later). The offset is VM timing, not guard behaviour, so 360 and 400 stand in for 240; the 240 result is a harness induction failure, not a guard failure.

Evidence: `qualification/clean-machine/windows/w08-tier2-sandbox-20261013/<run>/{log.txt,result.json,post.jpg}` (`sweep1` = first induction plus the pre-fix run where the task ran and logged nothing; `rep240-a`, `r240-a`, `r300-a` = induction failures). Live copies: `D:\Claude\swiftright\.sandbox\results\<job>\`. Crash evidence: Sandbox Application log event 1000, WER `ReportArchive`.

This is Sandbox evidence for the in-runtime guard, not independent review and not W08 closure; the release owner decision on RightKit ownership stands.

## Tier 2 repair guard v2: review findings closed (2026-10-13)

Independent review of the first guard found that nothing retried a failed repair (the feed-down run recovered only because the harness started the task by hand). Guard v2 closes that and the other findings. Ownership: the canonical script is RightKit `packages/release/msix-repair-guard.ps1` (commit `07081ba8`, unreleased, no version bump), exported by `msix-repair-guard.mjs` with its sha256; SwiftRightBridge embeds a byte copy pinned by `packages/SwiftRightBridge/guard/rightkit-pin.json` (sha256 `3df2415f...634b`; decision 6 in `docs/sr1-decisions.md`).

| # | Finding | Change | Proof |
|---|---|---|---|
| 1 | No retry after a failed repair | On exit 1 or 4 the script gives its own task a one-shot time trigger at +2, +5, +15, +60 min, then hourly, for at most 24 h from the first failure (`retry.json`); cleared on success, healthy package, uninstall | `g3-fd-a`: feed down at the cancel, back after 69.5 s, NO manual start; the retry fired at +2 min and the package was Ok 81.9 s after the feed returned |
| 2 | Uninstall cleanup only at logon/manual | Documented in the script header: cleanup runs at the next logon, next event 751, or next retry tick (no per-user "package removed" trigger exists); any run finding the package absent twice cleans up | `g3-uninst-retry`: failed first run (retry pending), `Remove-AppxPackage`, task and folder gone 133 s later with no manual start, `rows.json` kept; `g3-uninst`: 14.5 s after a manual start |
| 3 | Deleted task never re-registered | `needsInstall` also runs `schtasks /query /tn <PFN>-Repair` (CreateProcessW, hidden, off the main thread; a failed probe counts as "exists") | `g3-taskdel`: task deleted, the next launch registered it again in 4 s |
| 4 | Failed registration respawned PowerShell on every launch | `install-attempt.json` (epoch + script sha256) is written before the installer is spawned and removed by it on success; while it is under 24 h old and matches the embedded script no installer is spawned and `repair.log` says so | `g3-taskdel` phase 2: with a fresh marker and no task, a launch did not register it and logged `install skipped`; unit tests `testAttemptBackoffMarker` |
| 5 | Hardening | Feed, msix and redirect targets must be https, or http to a loopback host; `guard.json` must name `<PFN>-Repair` and the folder `repair`; Name and Publisher of the installed package are recorded at install and every feed, downloaded msix (manifest read from the zip before `Add-AppxPackage -Path`) and the package after repair must match, else `REFUSED` | `g3-wrongid`, `g3-corrupt` below |
| 6 | conhost `--headless` hides exit codes | `last-result.json` (status, code, mode, time, detail, next retry) and `install-result.json` next to `repair.log` | present in every run's `guard_after` / `guard_final` |
| 7 | Ownership | See above | RightKit `msix-repair-guard.test.mjs`; SwiftRightBridge `RepairGuardTests.testEmbeddedScriptIsThePinnedRightKitCanonicalFile` |

One more defect found while testing the negative controls: Windows PowerShell 5.1 renders a progress bar per chunk in `Invoke-WebRequest -OutFile`, so the 29 MB msix download took 6 minutes and timed out. The script now sets `$ProgressPreference = 'SilentlyContinue'`.

Acceptance and negative controls (Sandbox; packages `.work/w08t2/pkgs-t6`, `SliceApp.exe` built from the final `RepairGuard*.swift`, test publisher `CN=SwiftRight W08 Test`; the repair is never started by hand except in `g3-uninst`, which stands in for a logon). Evidence: `qualification/clean-machine/windows/w08-tier2-sandbox-20261013/g3-*/`. Offsets are ms after the staging directory appears; "attempts" counts induction tries before NeedsRemediation (induction is probabilistic and shifts with host load, so the harness walks an offset list starting at the requested one).

| Run | Offset requested -> induced at | Induced | Result | Seconds cancel to Ok | Launch / data / UI |
|---|---|---|---|---|---|
| g3-r360-a | 360 -> 360 (1st) | yes | repaired, 0.1.1.0 Ok | 13.3 | yes / sha equal / marker row shown |
| g3-r360-b | 360 -> 330 (2nd) | yes | repaired | 13.4 | yes / yes / yes |
| g3-r400-a | 400 -> 400 (1st) | yes | repaired | 14.0 | yes / yes / yes |
| g3-r400-b | 400 -> 360 (2nd) | yes | repaired | 12.8 | yes / yes / yes |
| g3-off200 | 200 (8 attempts) | no: 8/8 `old-ok`, Windows rolled back cleanly | n/a | n/a | n/a |
| g3-off280 | 280 -> 280 (2nd) | yes | repaired | 13.8 | yes / yes / yes |
| g3-healthy | none | n/a | guard did nothing: `healthy`, package full name unchanged, no `Add-AppxPackage` logged | n/a | n/a |
| g3-wrongid | 360 -> 360 | yes | feed (`OrthicLabs.OtherApp`) and msix both `REFUSED`, nothing installed (no OtherApp package), package stayed NeedsRemediation, `rows.json` unchanged; retry scheduled; after the good feed returned (61 s) the retry repaired it 85.5 s later | 146.6 | yes / yes / yes |
| g3-stale | 360 -> 330 | yes | feed serving only 0.1.0.0: recovers to 0.1.0.0 Ok (same-version `-AppInstallerFile`); no downgrade or refusal | 13.0 | yes / yes / yes |
| g3-corrupt | 360 -> 420 (5th) | yes | `-AppInstallerFile` failed 0x8007000D, downloaded msix `REFUSED: corrupt` (zip unreadable), explicit `FAILED`, package untouched, retry scheduled; good files restored at 61 s, retry repaired 85.8 s later | 147.0 | yes / yes / yes |
| g3-mutex | 360 -> 360 | yes | a second run of the script during the first run's settle window logged `another repair run is active`, exit 0; one repair, 0.1.1.0 Ok | 26.3 | yes / yes / yes |
| g3-kill, g3-kill-early | 270-420 and 0-250 (12 attempts each) | no: the client (AddPackageAsync in a child process) was killed at staging+delay; the deployment service finished the update regardless (24/24 `completed-anyway`, 0.1.1.0 Ok) | killing the client does not produce NeedsRemediation, so no guard action is needed | n/a | n/a |
| g3-base-reset (baseline, guard task removed) | 360 -> 390 (3rd) | yes | `Reset-AppxPackage` returned OK but the package stayed `Modified, NeedsRemediation`; app does not launch | n/a | no |
| g3-base-reg (baseline, guard task removed) | 360 -> 390 (3rd) | yes | relaunch only: the platform ran RegisterByPackageFullName but the package stayed NeedsRemediation; app does not launch | n/a | no |
| g3-fd-a | 360 -> 270 (6th) | yes | feed down at the cancel: explicit `FAILED ... feed unreachable ... msix unreachable`, retry 1 scheduled +2 min, package untouched until the feed returned at +69.5 s; retry repaired it, no manual start | 151.4 | yes / yes / yes |
| g3-uninst | none | n/a | task and repair folder removed 14.5 s after a manual start; `rows.json` and parent kept | n/a | n/a |
| g3-uninst-retry | 360 -> 360 | yes | cleanup by the retry tick alone, 133 s after `Remove-AppxPackage` | n/a | n/a |
| g3-taskdel | none | n/a | task re-registered by the next launch (4 s); with a fresh attempt marker it was not (logged) | n/a | n/a |

Offset 240 ms is not retested here (first guard: 16/16 `old-ok`); 200 ms is `old-ok` 8/8 and 280 ms inducible, so the working window in this Sandbox is about 270-420 ms. The retry trigger was verified gone after a successful repair (`guard_final.triggers` has only the event and logon triggers in `g3-wrongid`, `g3-corrupt`, `g3-mutex`).

Not proven here, and what contract closure still needs:
1. Release-signed packages bound to tuple 12 (source commit `0e201571...`, renderer candidate `7578CD5D...`): these runs use self-signed test packages (the sealed Tier 1 pair with a rebuilt `SliceApp.exe`, renderer `954977...` as in the first Tier 2 run); the guard needs one re-run on the signed old/new pair, with the signed package's real publisher, once the Azure reissue step produces it.
2. A RightKit version containing `msix-repair-guard.*` (bump and publish via the Rightkit Mac session), then `--sync` with the released version replacing `0.2.153+unreleased` in the pin.
3. The retry schedule beyond the first retry (+5, +15, +60, hourly, 24 h cut-off) is exercised by reading the script and the first retry only; a long-run test would take hours.
4. A real (non-Sandbox) Windows machine, including a locked-down one where `schtasks` or Task Scheduler is policy-blocked (the guard then does nothing and the 24 h installer backoff applies).
5. Independent review (Oracle) of this work; it has not been performed.

## Release-signed pair check (2026-10-14, CI run 38535084834)

Release-signed MSIX 0.1.0.0 (`2ef9dc7b...4050`) installs in the Sandbox on platform trust; package smoke, guard registration, healthy / task-deleted / uninstall controls PASS; signed DMG `9698efc5...0be4` notarized and stapled (read-only Mac checks). The positive repair and the update-based negative controls are NOT run: only one version is release-signed, and a cancelled update needs a newer one (a version 0.1.1 `release-candidate` run with signing would supply it; not dispatched, needs authorization). Receipt: `qualification/clean-machine/windows/w08-tier2-signed-20261014/RECEIPT.md`. W08 stays open.
