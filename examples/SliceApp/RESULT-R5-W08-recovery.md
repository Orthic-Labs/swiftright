# R5 W08 follow-up: recovering from `Modified, NeedsRemediation` after a cancelled MSIX update

Probe for RightKit. Not a harness check, not a product change. Evidence: `/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-w08-recovery/<run>/` (`result.json`, `log.txt`, `serve-local-feed.log`, `slice-app.log`, `rows.json`, screenshots, `.wsb`), harness copies in `.../harness/`. Working files on the Dell: `D:\Claude\sr0-r5\w08rec\` (staging copies of the MSIX were recycled; receipts kept).

## Setup

- Fresh Windows Sandbox per run (guest 10.0.26100.0, `Networking Enable`, vGPU disabled, same `.wsb` template as R5), one recovery method per run. Packages: `OrthicLabs.SliceApp` 0.1.0.0 (`clean\examples\SliceApp\dist\win`, sha256 4CC9A7F0...F2F4A, from 0751951) and 0.1.1.0 (`clean2\...`, C2897A68...2F432); script asserts both equal the `in2\` copies.
- Feed as in W12: guest-local https feed (`serve-local-feed.ps1`), `OnLaunch HoursBetweenUpdateChecks=0 ShowPrompt=false UpdateBlocksActivation=false`.
- Per run: trust signer, install 0.1.0.0 **through the feed** (`Add-AppxPackage -AppInstallerFile`), launch it and write the data marker row through UIA (`w08rec-<method>-marker` into `%LOCALAPPDATA%\SliceApp\rows.json`), publish the 0.1.1.0 `.appinstaller`, then loop: remove, reinstall 0.1.0.0 via the feed, `PackageManager.AddPackageAsync(file:///...new.msix)`, wait for the `OrthicLabs.SliceApp_0.1.1.0_*` staging directory under `WindowsApps`, sleep `+delay` ms, `IAsyncInfo.Cancel()`, settle, read `Get-AppxPackage`. Delay schedule cycles 240, 200, 280, 240, 220, 260, 230, 250, 210, 270, 245, 235, ... ms. Stop at the first `Status` containing `NeedsRemediation`.
- Then: confirm package state and that the app does not launch (explorer `shell:AppsFolder\<PFN>!App`, 45 s, UIA `Zed::Window` + process), apply ONE method, and record package status, launch (UIA window, version from the process image path, `slice-app.log` banner for that pid), data marker (file and UI row).

## Induction

| | |
|---|---|
| Runs that reached `Modified, NeedsRemediation` | 8 of 8 (a-2, a-3, a-4, b1-1, b2-1, c-1, d-1, d-2) |
| Cancels issued / produced NeedsRemediation | 31 / 8 (26%) |
| Attempts needed per run | 1, 1, 10, 13, 1, 3, 1, 1 |
| Other 23 cancels | all rolled back clean (0.1.0.0 `Ok`, data intact); failed state `Staged` 12, `StageUserDataProcessed` 6, `PackagesInUseClosed` 5; 0 completed anyway |
| NeedsRemediation, by delay | 225 ms 1/1, 240 ms 5/10, 270 ms 1/2, 280 ms 1/3; none of 200, 210, 220, 230, 235, 245, 250, 260 (n = 1 to 3 each) |
| First attempt of a run (follows the marker-write launch) | 5 of 8; attempts without a prior launch: 3 of 23 |
| Cancel timing of the 8 hits | 284 to 440 ms after `AddPackageAsync`; all 23 misses were between 284 and 422 ms, so the window is not sharp |

Mechanism (deployment-service log, e.g. `w08rec-a-4/result.json` attempt 10): the cancel lands in the `RegistrationChanged` state, `Error 0x80073CF8: Failure in the RegistrationChanged state handler`, then **`Warning 751: Windows failed to undo changes with error code 0x80073CF8 to package OrthicLabs.SliceApp_0.1.0.0... The package needs to be reinstalled`**. The rollback itself fails, so the old package stays registered as `Modified, NeedsRemediation`; `0.1.1.0` is moved to `WindowsApps\Deleted`.
State before every recovery attempt: `Get-AppxPackage` 0.1.0.0 `Modified, NeedsRemediation`, `rows.json` sha equal to the written one, marker present, and the package is still associated with the feed (`Package.GetAppInstallerInfo().Uri` = `https://localhost:8443/sliceapp/SliceApp.appinstaller`, read in d-2 after induction and after the relaunches).
Launch attempt before any method (all runs): no process, no window for 45 s, and Windows shows **"Can't open this app. You'll need to go to advanced options for SliceApp and select Repair. If you're still having issues with it, reinstall this app or contact your administrator."** with Close / Advanced options / Copy to clipboard (`pre-recovery-launch.jpg`; the dialog is not visible in the UIA root children).

## Result per method

| Method | Restores launch? | Version after | Data marker kept | Notes |
|---|---|---|---|---|
| (a) `Add-AppxPackage -RegisterByFamilyName -MainPackage OrthicLabs.SliceApp_j3cejpx244dcr` | **No** | 0.1.0.0, still `Modified, NeedsRemediation` | yes (file sha unchanged) | Cmdlet returns OK in about 2 s, logs no deployment operation, changes nothing; app still shows "Can't open this app". Same in 3 runs (a-2, a-3 partial, a-4 full) |
| (b1) `Add-AppxPackage -AppInstallerFile <feed uri>` (feed = 0.1.1.0) | **Yes** | **0.1.1.0 `Ok`** | yes (file sha identical, marker row in UI) | `AddFromAppInstallerOperation`, 3 s, update 0.1.0.0 to 0.1.1.0; window `SliceApp` up in 1 s from `...OrthicLabs.SliceApp_0.1.1.0...\SliceApp.exe`, log banner for the new pid |
| (b2) `Start-Process "ms-appinstaller:?source=<feed uri>"` | **Not testable here** | unchanged | yes | Stock Sandbox has no `Microsoft.DesktopAppInstaller`, `ms-appinstaller` is not registered, policy key `EnableMSAppInstallerProtocol` not set. Start-Process returns without error and Windows opens the **"Pick an app"** Open With dialog; no App Installer UI, nothing to drive, package unchanged (`b2-appinstaller-ui.jpg`). The real UI (the Dell host has App Installer 1.29.380.0 with the protocol registered, read-only check) was not exercised: it would need a guest with App Installer (e.g. a Sandbox with the package added), or a human on a real machine. b1 covers the same deployment call chain |
| (c) `Get-AppxPackage OrthicLabs.SliceApp \| Reset-AppxPackage` | **No** | 0.1.0.0, still `Modified, NeedsRemediation` | yes | Returns OK in 2.6 s; service log shows Remove and StageUserData with `RepairAppRegistrationOption` ("Skipping some operations ... due to repair"). Did not repair and did not wipe: package-private file count 2 before and after, `rows.json` identical (data lives in `%LOCALAPPDATA%\SliceApp`, outside the package container; the app is manifest-unvirtualized) |
| (d) relaunch the app (OnLaunch feed) | **No** | 0.1.0.0, still `Modified, NeedsRemediation` | yes | 2 relaunches x 40 s plus 90 s observation each, in 2 runs (d-1, d-2): no window, "Can't open this app" again, **0 feed requests** after the initial install (activation fails before any App Installer update check, even though the association is intact). Feed declares `UpdateBlocksActivation="false"`; the `true` variant was not run |

Reading: of the four requested methods only the **App Installer deployment call on the newer `.appinstaller` (b1)** recovers, and it recovers by updating, not repairing (0.1.0.0 becomes 0.1.1.0, user data untouched). In-place re-registration (a), reset (c) and relaunch (d) leave the package unlaunchable. Windows' own advice ("Advanced options ... Repair") is the Settings Repair button, which was not driven here (not in the requested list; I know of no cmdlet for it, unverified).

## Harness notes and deviations

- `w08rec-a-1`: guest aborted at start (empty `$PSScriptRoot` in a param default); no data. `a-2` and `a-3`: guest hung in the final `ConvertTo-Json` (Get-Content strings carry PSProvider note properties); induction and recovery were already recorded (`result.json` before the hang, `post` state from `log.txt`: package unchanged, no launch, marker in file). `a-3` was ended by the new watchdog after 367 s without a heartbeat; `a-2` I ended by stopping the `WindowsSandboxRemoteSession` process (PID 34388) that run started (its `WindowsSandboxServer` child and `vmmemWindowsSandbox` exited with it) plus that run's orphaned start-run/launch processes and one-shot scheduled task. `a-4` is the clean method-(a) run.
- New harness in `D:\Claude\sr0-r5\w08rec\` (not the committed R5 harness): `w08rec-guest.ps1`, `w08rec-watchdog.ps1`, `run-w08rec.ps1`, `start-run.ps1` (non-elevated scheduled task via `run-unelevated-step.ps1`), `chain.sh`, `collect.sh`. The R5 harness files and the repo are unchanged; no commits.
- Induction used `AddPackageAsync` with the MSIX path from the read-only mapped packages folder (as in W08), but the old version was installed via the feed rather than `-Path`, so the App Installer association was present for (d). Loopback https feed, self-signed cert in the guest Root store; production App Installer host and TLS chain remain untested.
- One data point per method for (a) to (c) beyond the repeat runs; the state space (cancel phase `RegistrationChanged` only) is the single case that yields NeedsRemediation in these 31 cancels, not a proof it is the only one.
