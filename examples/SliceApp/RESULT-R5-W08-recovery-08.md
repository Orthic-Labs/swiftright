# R5 W08 recovery on the final packages (tuple 08), 2026-10-10

Question (docs/sr0-findings.md T12): after the W08 interrupted update leaves `OrthicLabs.SliceApp` 0.1.0.0 as `Modified, NeedsRemediation`, which user-accessible recovery works on the FINAL packages, and what are package status, relaunch, version and data afterwards?

**Answer in one line.** Settings > Advanced options > Repair, a same-version `Add-AppxPackage -Path`, and a same-version `Add-AppxPackage -AppInstallerFile` each recovered the package (launches, data intact). `Reset-AppxPackage` and the platform's own `RegisterByPackageFullName` did not. W08 itself stays FAIL: the harness still leaves the package unlaunchable until one of these is applied.

## Setup

- Packages: tuple 08 MSIX pair in `D:\Claude\sr0-r5-08\in` (0.1.0.0 sha256 `C80C6947…A0C4`, 0.1.1.0 `0FF65165…C8E8`; renderer E280F4A9). `run-w08-recovery.ps1` refuses any other bytes (hash check before every run). Feed files are the R5-08 `SliceApp.0/1.appinstaller` (localhost https, `OnLaunch HoursBetweenUpdateChecks=0 ShowPrompt=false UpdateBlocksActivation=false`).
- One fresh Windows Sandbox per method (guest 10.0.26100.0, networking enabled, same `.wsb` template as R5, vGPU disabled), run non-elevated in the interactive session under `D:\Claude\desktop.lock`.
- Per run: trust signer, install 0.1.0.0, write a data marker row through the app UI (UIA), publish 0.1.1.0, then cancel `PackageManager.AddPackageAsync(0.1.1.0)` at staging+delay (delays 200 to 280 ms, retried) until `Get-AppxPackage` shows `Modified, NeedsRemediation`. Then ONE method, then package status, relaunch (UIA window, version from the process image path, `slice-app.log` banner), and data (`rows.json` sha equal to the written one and the marker row shown in the UI).
- Induction needed 1 to 28 cancels (28, 1, 1, 1, 3, 1, 1, 3 across the runs in the order settings-repair, reset, reinstall-same-1, appinstaller-same, platform-register, settings-repair-same, reinstall-same-2, settings-repair-path); every run reached `Modified, NeedsRemediation` at `RegistrationChanged`.
- Install route: the feed (`Add-AppxPackage -AppInstallerFile`, App Installer associated) except `settings-repair-path`, which installs 0.1.0.0 with `Add-AppxPackage -Path` and serves no feed (the W08 offline scenario).

## Results

| Req | Method (run) | Package after | Relaunch | Version | Data |
|---|---|---|---|---|---|
| (a) | Settings Repair, feed serves 0.1.1.0 (`t12-settings-repair-1`) | `0.1.1.0 Ok` within 3 s | yes, from `WindowsApps\…0.1.1.0` | **0.1.1.0** | intact |
| (a) | Settings Repair, feed serves 0.1.0.0, no newer version (`t12-settings-repair-same-1`) | `0.1.0.0 Ok` within 3 s | yes | 0.1.0.0 | intact |
| (a) | Settings Repair, path install, no feed (`t12-settings-repair-path-1`) | `0.1.0.0 Ok` within 3 s | yes | 0.1.0.0 | intact |
| (b) | platform `RegisterByPackageFullName`, no action of ours (`t12-platform-register-1`) | **still `Modified, NeedsRemediation`** | no window at either 45 s launch attempt or the 60 s final relaunch | 0.1.0.0 | intact |
| (c) | `Reset-AppxPackage` (`t12-reset-1`) | **still `Modified, NeedsRemediation`** | no window in 60 s | 0.1.0.0 | intact |
| (c) | `Add-AppxPackage -Path` same 0.1.0.0 MSIX (`t12-reinstall-same-2`) | `0.1.0.0 Ok`, 2.6 s | yes | 0.1.0.0 | intact |
| (d) | `Add-AppxPackage -AppInstallerFile`, feed declares 0.1.0.0 (`t12-appinstaller-same-1`) | `0.1.0.0 Ok`, 3.6 s | yes | 0.1.0.0 | intact |

"Intact" = `rows.json` sha256 equal to the one written before the cancel, marker row visible in the relaunched UI, banner for the new pid in `slice-app.log`.

### (a) Settings Repair, how it was driven and what it did

- All through UIA of the Settings app in the guest, no pointer or keyboard injection. The three `ms-settings:appsfeatures-app…` URI forms tried (plain, `?PackageFamilyName=<pfn>`, `?<pfn>`) all open only the Installed apps list; none reaches Advanced options or a Repair button. The route that works: `ms-settings:appsfeatures` > search box (ValuePattern) "SliceApp" > the row's "More options" (Invoke) > "Advanced options" menu item (Invoke) > button `SystemSettings_StorageSense_AppSizesAdvanced_AppRepair_Button` "Repair" (off-screen, scrolled into view with ScrollItemPattern, then Invoke). The "Reset" button on the same page was not touched. UIA dumps and screenshots of every page are in each run's `settings-*.txt/jpg`.
- What Repair does (AppX deployment log, `RepairPackageOperation`): step 1 is an Add of the package from its recorded install source, step 2 is `RegisterByPackageFullName` (RepairAppRegistrationOption).
  - Feed-installed, feed offers 0.1.1.0: the Add is `AddFromAppInstallerOperation … ApplyToExistingPackages`, which UPDATES 0.1.0.0 to 0.1.1.0 (the old folder moves to `WindowsApps\Deleted`); step 2 then fails with 0x80073CF1 because 0.1.0.0 is gone, and the end state is nevertheless good (0.1.1.0 Ok). So with a newer version published, "Repair" recovers by updating.
  - Feed-installed, feed offers 0.1.0.0: the Add re-adds the same 0.1.0.0 from the feed; status is cleared (`Clear=0x2000439F`), step 2 succeeds.
  - Path-installed, no feed: the Add re-adds from `file:///…/old.msix`, the original install source; status cleared, step 2 succeeds. The source file was still present.

### (b) Platform registration

The deployment service ran `RegisterByPackageFullName` (Options `ForceTargetApplicationShutdownOption, RepairAppRegistrationOption`, "ACLs repaired successfully", finished in about 150 ms) at each launch attempt on the NeedsRemediation package: 19:20:50 (first attempt, about 1 s after it started) and 19:21:46 (second attempt). Both "finished successfully" and neither changed the status: still `Modified, NeedsRemediation` after a further 150 s of observation, and the final relaunch (60 s) showed no window. So the registration seen at the end of the R5-08 hold is not a recovery. It is triggered by a launch attempt, not by elapsed time: the hold in this run ended at once because the first attempt's register event was already in the log, and the observation after the second attempt (about 4 minutes in total) is what the table reports.

### (c) and (d), notes

- `Reset-AppxPackage` returns OK in 2.6 s; the log shows Remove + StageUserData + Register with RepairAppRegistrationOption ("Skipping some operations … due to repair"). Package status unchanged. The package-private folder under `%LOCALAPPDATA%\Packages\<pfn>` went from 4 files to 2; the app's data (`%LOCALAPPDATA%\SliceApp\rows.json`, outside the package container) was untouched.
- `Add-AppxPackage -Path` with the same version is accepted while the package is NeedsRemediation (no downgrade or "already installed" refusal in that state) and clears it.

## Invalid or superseded runs, kept

- `t12-reinstall-same-1`: NOT a test of (c). The pre-method launch attempt (explorer `shell:AppsFolder`, 45 s) was followed by App Installer downloading 0.1.1.0 from the feed (range requests from Delivery Optimization at 19:15:28, about 10 s after NeedsRemediation) and the package was `0.1.1.0 Ok` when the probe ended, so `Add-AppxPackage -Path` 0.1.0.0 was refused with 0x80073D06 ("a higher version is already installed"). This shows that a plain launch attempt CAN recover the package through the feed's OnLaunch update when a newer version is published. It did not happen in the other four runs that had the same launch attempt (`settings-repair-1`, `reset-1`, `appinstaller-same-1`, `platform-register-1`), and the earlier RightKit probe saw 0 feed requests on relaunch (`RESULT-R5-W08-recovery.md`, method d). The trigger was not isolated (one occurrence in five).
- After that the harness stopped launching before the method (except `platform-register`, where launching is the experiment) and checks `needs_remediation_at_method_start`. `settings-repair-1`, `reset-1`, `appinstaller-same-1` ran with the earlier version that did launch first; each was still NeedsRemediation after that launch, so they are valid. `t12-probe-1` is the Settings UI probe (no recovery).
- Guest harness versions by run (sha256 prefix of `w08-recovery-guest.ps1`): `settings-repair-1` 051b23a2; `reset-1`, `reinstall-same-1`, `appinstaller-same-1` fa89e050; `platform-register-1`, `settings-repair-same-1`, `reinstall-same-2` 89fb5ec1; `settings-repair-path-1` 4e3b5aad (the committed copy, beadda8f, differs from it only in the text of one `command` note for path mode, which the `settings-repair-path-1` record words as if the feed were serving 0.1.1.0; it was not served).

## Limits

- n = 1 per method and per install route; induction is by a timing cancel, only the `RegistrationChanged` failure produced NeedsRemediation, so these results are for that state.
- Repair needs its install source: the feed (reachable, https, trusted) or the original MSIX path. Repair with the source gone (feed down, MSIX file deleted) was not tested. The feed is a guest-local loopback server with a self-signed root in the guest store; the production App Installer host and TLS chain are untested.
- Windows Sandbox guest, one OS build (10.0.26100). Settings behaviour on a real Windows install, with a non-admin user, or on a different Windows version is not covered.
- A user would have to find the Repair button by themselves: Windows' own message on launch is "Can't open this app. You'll need to go to advanced options … and select Repair" (RESULT-R5-W08-recovery.md); this run confirms that route works. The product itself does nothing to repair or to tell the user.

## Harness (commit-ready, `qualification/clean-machine/windows`)

- `guest/w08-recovery-guest.ps1`, `guest/w08-recovery-watchdog.ps1`, `guest/logon-w08-recovery.cmd`: the guest (methods `settings-repair`, `settings-repair-same`, `settings-repair-path`, `platform-register`, `reset`, `reinstall-same`, `appinstaller-same`, `settings-probe`).
- `run-w08-recovery.ps1`: host launcher for one run (stages harness and packages, hash-checks the MSIX pair, writes the `.wsb` from `clean-machine.wsb.tmpl`, starts the Sandbox, waits for `receipts\DONE`). Nothing is deleted or recycled.
- `run-unelevated-task.ps1`: runs a command as the logged-in user, non-elevated, in the interactive session (one-shot task, disabled afterwards, never deleted). `with-desktop-lock.ps1`: waits for `D:\Claude\desktop.lock` to read `free`, takes it, runs a script, writes `free` in a `finally`.
- `sandbox-background.ps1` (host-desktop rule from the Dell's owner, applied from `run-w08-recovery.ps1`): sends every `WindowsSandboxClient` / `WindowsSandboxRemoteSession` window to `HWND_BOTTOM` with `SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE` (never minimized), and gives the foreground back to the window that had it. It runs one pass every 150 ms from before the Sandbox starts until it is gone. Restoring the foreground needed an escalation: `SetForegroundWindow` alone failed on every attempt against the active Sandbox window (391 failures in `reinstall-same-2`), and attaching to the foreground thread's input queue (`AttachThreadInput`, no input injected) made it succeed with 0 failures in `settings-repair-path-1` (Sandbox pushed back and the foreground returned within about 0.4 s of the window first being seen). Runs through `settings-repair-same-1` and `reinstall-same-2` predate the working version; during those the Sandbox window could take the foreground. Window titles are never read.

Evidence: Dell `D:\Claude\sr0-t12\runs\<run>\receipts\` (result.json, log.txt, settings dumps and screenshots, feed log, `rows.json`, `slice-app.log`) and a copy at `/Volumes/D/sr0-artifacts/win/r5-08-w08-recovery/<run>/` with the harness as run (`harness/`). No window titles of the host were recorded; Settings dumps are of the disposable guest.
