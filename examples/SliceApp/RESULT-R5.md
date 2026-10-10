# R5 Windows Sandbox clean-guest result, final2 round (2026-10-10)

Host: Dell (Bogus-Dell, Windows 11 24H2 build 26100.9550). Guest: Windows Sandbox (Store app 0.8.107.0), guest OS 10.0.26100.9550, `<vGPU>Disable</vGPU>` (software rendering; see "Environment"). Two runs, because W12 needs a connected guest and W01 to W04 must never see a network:

| Run | Profile | Networking | Checks | Run id | run.json sha256 | Guest harness sha256 |
|---|---|---|---|---|---|---|
| Offline | `Offline` | `Disable` (W00: 0 default routes) | W00 to W11, W13, W14 | `r5-final2-offline-4` | 329a2d84e8c6c0fde1497d0118f7052370a8065573d112e299a71b48096960d1 | 42d095535d76eb956657fcd4b157e14be7e8bae219aa0b7b4472b0498a37aa42 |
| Network | `Network` | `Enable` (W00: 1 default route) | W00, W01, W12 | `r5-final2-network-2` | e21305cd5439b7f2ddf1cb1934aeafac7dd641e8d8ba8c4ad82742117548a3f9 | 42d095535d76eb956657fcd4b157e14be7e8bae219aa0b7b4472b0498a37aa42 |

Host harness `run-sandbox.ps1` sha256 c3305a704d2d93ed85e7cbb861957f41979c1e681a6f7a0a3734b0015694e4aa (both runs started through the non-elevated one-shot Interactive/Limited task, `logs/log-sandbox-r5-final2-*.txt` first line `elevated=False`). The harness changes (four files, listed below) are UNCOMMITTED working-tree changes on top of 0751951 (copies and the diff are in `harness/`). Artifacts and logs: `/Volumes/D/sr0-artifacts/win/r5-final2/` (every path below is relative to it).

**Verdict: R5 is NOT PASS. 14 of 15 checks PASS; W08 FAILS** (an update cancelled in the registration phase leaves the previous version unlaunchable until the update is re-applied; data intact, recovery works). Nothing is NOT-DEMONSTRABLE any more except the Stop-Process interrupt method on its own (see W08). The package, signature, renderer pin and the product fix are good.

## Product fix (P1, commit 0751951623d962e15ea3ce2c5fd7f56db6f592df, pushed to master)

`SliceApp.exe` was a console-subsystem exe, so a packaged launch opened a `ConsoleWindowClass` window. Now:
- `scripts/build-windows.ps1` passes `-Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup` (Swift's `@main` emits C `main`; `/SUBSYSTEM:WINDOWS` alone makes the linker look for `WinMain`) and fails closed unless the PE Subsystem field is 2. Consumer link flags, no `unsafeFlags` in `Package.swift`.
- `Sources/SliceApp/Windows/WindowsLog.swift` + one call at the top of `main`: when stdout or stderr has no usable handle (packaged launch), the C stream and process standard handle are pointed at `%LOCALAPPDATA%\SliceApp\slice-app.log` (else `%TEMP%`), unbuffered, with a first line `slice-app: log opened <utc> pid=<pid> exe=<path>`. Pipes, files and consoles are left alone, so the QA driver's `SWR_`/`SLICE_` diagnostics still arrive.
- `scripts/verify-package-layout.ps1` (Stage and Installed modes) rejects a console-subsystem exe.
- Verification (headless, Dell, on the signed payloads unpacked from the final MSIX, PATH = System32 only, renderer removed so the app exits 78 at once; `logs/log-headless-logging-test.txt`): PE subsystem 2; pipes give the diagnostic on stdout and create no log; no handles give banner plus diagnostic in the log and a second launch appends; stdout to a file with stderr detached keeps the diagnostic in the file and logs the banner; no `LOCALAPPDATA` falls back to `%TEMP%`. The previous console stage is rejected by the new check (subsystem 3).
- In the Sandbox (W04, 0.1.0 packaged, AUMID launch): window `SliceApp`, PE subsystem 2, 0 console windows naming SliceApp, banner for the running pid in `slice-app.log`. Negative control (`probes/P40`, the previous round's console build 85bea609...): subsystem 3, one `ConsoleWindowClass` window titled with the exe path, no log: the W04 check can fail.
- **Known limit of the shipped commit:** the CRT's `freopen` opens the log exclusively, so it cannot be read while the app runs (W04 closes the app first, then reads it). A shared-read variant (`CreateFileW` with `FILE_SHARE_READ|WRITE|DELETE` + `_dup2`) compiles and passes the same headless tests; it is NOT committed (one commit was authorised) and NOT in the packages: `candidate-WindowsLog-shared-read.swift` / `.patch`. Apply it in a follow-up commit if live log reading matters.

## Inputs (all PASS)

| Item | Result |
|---|---|
| Build commits | clone `clean` (0.1.0): 0751951623d962e15ea3ce2c5fd7f56db6f592df on branch `master` (git bundle of the pushed master; Dell HTTPS auth is broken). Clone `clean2` (0.1.1): clone-local commit b545c34f13f3a91b48d1096d688af057bd767d94 on top of 0751951 (`bump-version-win.ps1`: version fields + one Swift diagnostic string) |
| QA source receipts (@rightkit/release 0.2.144) | 0.1.0 digest 4e07cf051b96c500b144c64391abc38c90f2267c565017a75f9e82d30426d559, 0.1.1 digest 05bf97ddbfc65620e57aea22f44a05ee9684b1e7e362c5b93c8366679eb90ba2; each `app.build`, `app.launch`, `journey.restart-keeps-data` passed (`qa-receipts/`, `inputs/log-qa-*.txt`) |
| SliceApp_0.1.0.0_x64.msix | sha256 4cc9a7f0a05c05561432ddf536179ae18b6e2aeabbc0f6c245397de38edf2f4a (29,048,635 B), equals seal `sliceapp-0.1.0-07519516` |
| SliceApp_0.1.1.0_x64.msix | sha256 c2897a68d1a4555da92155f4192dc53c77a5803e5932a821ab3fed465de2f432 (29,048,705 B), equals seal `sliceapp-0.1.1-b545c34f` |
| Seals | `inputs/msix-seal-0.1.{0,1}.json` (148039fc..., afc81bf1...), `inputs/release-manifest-0.1.{0,1}.json` |
| `signtool verify /pa /v` both | Successfully verified, exit 0, 0 warnings; chain Microsoft Identity Verification Root CA 2020 > ID Verified Code Signing PCA 2021 > ID Verified CS AOC CA 03 > Damned Ventures LLC (SHA1 121FD7B569E256DA0AF63B1BF8E3CD5AEDF888D3); RFC3161 timestamps 06:03:48 / 06:06:10. `log-host-verify.txt` |
| `verify-package-layout.ps1 -Mode Stage` on both unpacked payloads (27 files) | OK both: renderer beside exe, Authenticode digest = pin D8FB3B3B... (ABI 0.6; raw sha256 in the packages 3658385B... / F13AAD22..., both Valid), exe subsystem 2 and Valid |
| `swift-only-proof.mjs` 0751951 vs b545c34f (`--repo clean2`, QA logs as build logs) | `ok: true`; changed payload = `appxmanifest.xml`, `sliceapp.exe` only; renderer digest equal and = pin. `log-swift-only-proof.txt` |
| App Installer feeds (`make-local-appinstaller.mjs`, RightKit 0.2.144) | `feed/SliceApp.0.appinstaller` 87d7e8cd6801a0bd8696a94492c1e39c150f213ecb606f5483498548c00d04c6, `feed/SliceApp.1.appinstaller` 5eb7059488a6ff705262..., unchanged from the previous round (they depend only on identity and version) |

The first `build` of each clone was refused by RightKit ("version 0.1.0 already sealed from commit 54d480c4; bump the version before rebuilding"). The previous round's sealed directories were moved out of the clones' `.right-release\sealed` into `D:\Claude\sr0-r5\archive\r5-final-seals\` (copies of those packages and seals are in `/Volumes/D/sr0-artifacts/win/r5-final/inputs/`); no RightKit file was edited, the versions stay 0.1.0 and 0.1.1.

Signing certificate (this round): Damned Ventures LLC, thumbprint 121FD7B5..., expires **2026-10-12 05:16:54 (Dell local, +05:30)**; the previous round's certificate (70C72673...) was a different one. Installs keep validating through the RFC3161 timestamp, but any new build needs a renewed certificate.

## Results per check

| Check | Run | Result | Notes |
|---|---|---|---|
| W00 environment | offline / network | PASS / PASS | offline: elevated, 0 default routes. network: elevated, 1 default route (adapter Ethernet) |
| W01 artifacts bound | offline / network | PASS / PASS | old, new, cer, feed, scripts hashes = host manifest |
| W02 signer trust | offline | PASS | `Valid` offline, no import |
| W03 install old (plan "install") | offline | PASS | 0.1.0.0 registered |
| W04 launch offline (plan "offline launch") | offline | PASS | window `SliceApp`, renderer loaded from the package directory, 0 default routes; NEW: PE subsystem 2, 0 console windows, log banner for the pid |
| W05 write data | offline | PASS | marker in `%LOCALAPPDATA%\SliceApp\rows.json`, no `Packages\...\LocalCache` copy |
| W06 upgrade 0.1.0 to 0.1.1 (local msix) | offline | PASS | version 0.1.1.0, rows.json hash unchanged by install, marker shown, new build wrote its own row |
| W07 corrupt update rejected | offline | PASS | bit flipped inside `SliceApp.exe` refused (0x80080207, block hash mismatch), 0.1.0.0 stayed, genuine 0.1.1.0 then applied |
| **W08 interrupted update** | offline | **FAIL** | see below |
| W09 rollback readable | offline | PASS | old build reads data written by the new build; schema 1 |
| W10 uninstall keeps data | offline | PASS | rows.json byte-identical after removal, no LocalCache copy |
| W11 legacy data / physical path | offline | PASS | manifest `FileSystemWriteVirtualization=disabled` + `unvirtualizedResources`; legacy rows.json read and edited in place |
| W12 App Installer feed install + OnLaunch update | network | **PASS** | see below |
| W13 installed renderer layout | offline | PASS | static check on the install location (digest = pin) now also requires subsystem 2 |
| W14 update deferred while running | offline | PASS | `-DeferRegistrationWhenPackagesAreInUse`: 0.1.0.0 stays while running, 0.1.1.0 after relaunch, data unchanged |

### W08 (FAIL): interrupted update, real interruption in the guest, no reboot

Method (`scripts/interrupt-windows-install.ps1`, modes `KillClient` and `CancelOperation`; receipt `receipts-offline-4/W08-interrupted-update.json`, per-case evidence `receipts-offline-4/evidence-W08-c*.json` with timelines and AppXDeploymentServer events). Eleven cases, each: remove, install 0.1.0.0, start the update to 0.1.1.0, interrupt when the new version's staging directory appears under `C:\Program Files\WindowsApps` plus a delay, then judge the live state, `rows.json` hash, launch of the registered build through UIA, and a second `Add-AppxPackage` of 0.1.1.0.
- **KillClient** (`Stop-Process -Force` on the `powershell.exe` running `Add-AppxPackage`, at staging+0 and +150 ms, client alive at the kill): NOT an interruption. The deployment service finishes the update anyway (0.1.1.0 Ok in both cases, in every run). On its own this method is NOT-DEMONSTRABLE. (AppXSvc cannot be killed either, previous round H7.)
- **CancelOperation** (the documented WinRT route: `PackageManager.AddPackageAsync` cancelled with `IAsyncInfo.Cancel()`; the service logs "cancelled by the caller", error 0x80073CF8): the deployment is about 0.5 s long; cancels at staging+0, +160, +200, +240, +280, +300, +320, +360 ms and immediately after the call. Final run: 5 genuine interruptions (old version registered, new version not), the +280 ms and later ones were too late (completed anyway).
  - 4 of 5 (the service reports failed to reach state `PrerequisitesChecked`, `PackagesInUseClosed`, `StageUserDataProcessed`, `DeQueued`): old 0.1.0.0 stays registered with status Ok, data intact, it launches, the second update registers 0.1.1.0 Ok.
  - **1 of 5 (cancel at +240 ms, failed to reach state `RegistrationChanged`)**: 0.1.0.0 stays the only registered version but with status **`Modified, NeedsRemediation`**; the build does NOT launch (no window within 40 s); `rows.json` is byte-identical; a second `Add-AppxPackage` of 0.1.1.0 completes and registers it Ok.
  - Reproducible but timing dependent (the phase window is about 200 to 280 ms after staging appears): the earlier iterations of the same harness showed it in 1 of 4 genuine interruptions (`receipts-offline-2`) and 3 of 6 (`receipts-offline-3`, +200, +240, +280 ms), always with data intact and always recovered by the second update.
- Verdict FAIL by the stated criteria (previous version still launches, data intact, second update completes): the first does not hold for cancels landing in the registration phase. This is platform (MSIX deployment) behaviour that the package cannot change; recovery is re-running the update (the App Installer route does that on the next launch), data is never touched. No guest power-off was attempted: Sandbox state is discarded on close, so it could not be inspected.

### W12 (PASS): App Installer route, networking enabled

`receipts-network-2/W12-appinstaller-update.json` (`receipts-network/` is the same result from the previous harness iteration). Loopback https feed inside the guest (`serve-local-feed.ps1`, self-signed `CN=localhost` in the guest Root store), Delivery Optimization no longer stalls once the guest has a network profile (previous round H8 was the missing connectivity, not the feed): a feed whose Publisher differs from the signer is rejected (0x8008020C, ".appinstaller file is invalid"), nothing installed; the correct 0.1.0.0 feed installs; swapping to the 0.1.1.0 feed and relaunching (`OnLaunch HoursBetweenUpdateChecks=0`) registers 0.1.1.0; `rows.json` hash unchanged. Production App Installer host and TLS chain remain UNTESTED.

## Harness changes in this round (uncommitted, `harness/`)

`run-sandbox.ps1`: `-RunProfile Offline|Network` (checks per profile, `__NETWORKING__` token in the .wsb template, `profile` in manifest.json). `guest/sandbox-run.ps1`: profile-aware W00 and check list; verdict PASS/FAIL/NOT-DEMONSTRABLE in `observations.verdict` (the receipt schema only has pass|fail, so NOT-DEMONSTRABLE would be a fail receipt with that reason); W04 console and log checks; W08 rewritten (per-case judging); `Write-MarkerRow` polls up to 15 s for the new empty row (software-rendered guest). `interrupt-windows-install.ps1`: `KillClient` and `CancelOperation` modes (one attempt per call). `clean-machine.wsb.tmpl`: networking token, stale vGPU comment fixed. `build-windows.ps1` and `verify-package-layout.ps1` are the committed 0751951 versions.

Iterations kept as evidence: `receipts-offline-1` (W04 log read hit the exclusive log; W08 first draft), `receipts-offline-2` (W04 same, W08 1 bad case of 4 genuine), `receipts-offline-3` and `receipts-network` (same harness logic as the final runs, 13 of 14 plus W12 PASS, W08 3 bad cases of 6 genuine; superseded because the harness variable layout was then changed to satisfy `qualification/test_run.py` HarnessDriftTests, 74/74 pass, and both runs were repeated so the receipts bind to the final files). Host console output of every run: `logs/host-output-*.txt`.

## Environment and limits

- `<vGPU>Default</vGPU>` drops the guest's RDP session on this Dell (previous round); all runs use `Disable`, so rendering is software (display adapter "Microsoft Remote Display Adapter"). Hardware-GPU rendering in the guest is not covered.
- The final two runs, the builds and QA ran through the non-elevated one-shot task (`elevated=False` in their logs). The earlier iterations and the probes were started from the SSH admin session (`WindowsSandbox.exe <wsb>`) because a quoting slip (`-Cmd ''& ...''` through `sh`, then PowerShell 7 reads the bare `&` as a background operator) skipped the wrapper; the guest is unaffected.
- Production App Installer host and TLS chain (W12 used a guest-local self-signed feed); hardware GPU; the shared-read log variant (candidate only); a guest power loss during deployment (not inspectable in Sandbox); the AppXSvc stop (fault injection, did not interrupt).
- Probe evidence (not harness evidence): `probes/` (`P31` first W08 attempt, `P32`/`P36`/`P37` phase surveys, `P38` W12 with networking, `P40` console negative control, `guest-probe*.ps1`).
- The previous round's results (pinned harness 5 of 15, patched harness 13 of 15; defects H1 to H8) are superseded by this table; H7 and H8 are resolved as described above, and P1 is fixed.

## Files

`inputs/` (msix, seals, release manifests, QA logs), `qa-receipts/`, `feed/`, `log-host-verify.txt`, `log-swift-only-proof.txt`, `log-appinstaller-gen.txt`, `logs/`, `receipts-offline-{1,2,3,4}/`, `receipts-network{,-2}/`, `probes/`, `harness/` (the harness files as run and `harness-final2-vs-0751951.patch`, sha256 c929bfc851e1dfcd65913f42a76a7c806fd0176434117972107131f6c9c6d12b), `candidate-WindowsLog-shared-read.{swift,patch}`. Dell working files remain in `D:\Claude\sr0-r5` (clones `clean`/`clean2` with the new seals, `in2`, `harness2`, `runs`, `probe`, `archive`); scratch dirs went to the Recycle Bin.
