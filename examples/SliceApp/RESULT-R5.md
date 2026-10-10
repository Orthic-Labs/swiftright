# R5 Windows Sandbox clean-guest result (2026-10-10)

Host: Dell (Bogus-Dell, Windows 11 24H2 build 26100.9550), non-elevated one-shot Interactive/Limited task for every Sandbox launch, no upload. Guest: Windows Sandbox (Store app 0.8.107.0, installed by the first launch), guest OS 10.0.26100.9550, offline (`Networking Disable`, W00 confirms 0 default routes).
Harness: pushed commit 54d480c (`run-sandbox.ps1` sha256 7cb1f2f2..., guest `sandbox-run.ps1` sha256 5cc7207e...). Artifact dir: `/Volumes/D/sr0-artifacts/win/r5-final/` (all paths below are relative to it).

**Verdict: R5 is NOT PASS.** The pinned harness (with the one environment change below) passes 5 of 15 checks (W07 only vacuously); 10 fail on harness or environment defects. With a patched harness (patch: `examples/SliceApp/RESULT-R5-harness.patch`) 13 of 15 pass; W08 and W12 cannot be demonstrated in this guest. Packages, signatures and renderer pin are good.

## Inputs (host-side verification, all PASS)

| Item | Result |
|---|---|
| SliceApp_0.1.0.0_x64.msix | sha256 85bea609fef423544bda408e60e304b7790959ffc24229e8460f9a198dbcdb7a (29,038,137 B), equals seal `sliceapp-0.1.0-54d480c4`; clone commit 54d480c4 |
| SliceApp_0.1.1.0_x64.msix | sha256 893a3ec499ab35a9aec31fcda50153a07b8d9e661ae9d4f08ab682158b41a2bc (29,038,011 B), equals seal `sliceapp-0.1.1-f1e35e9f`; clone commit f1e35e9f |
| `signtool verify /pa /v` both | Successfully verified, exit 0, 0 warnings; chain Microsoft Identity Verification Root CA 2020 > ID Verified Code Signing PCA 2021 > ID Verified CS EOC CA 03 > Damned Ventures LLC (70C72673...); RFC3161 timestamps 03:26:40 / 03:29:15. `log-host-verify.txt` |
| `verify-package-layout.ps1 -Mode Stage` on both unpacked payloads (makeappx unpack, 27 files each) | OK both: renderer beside exe, Authenticode digest = pin (D8FB3B3B..., ABI 0.6; raw sha256 in packages 6C80D968... / 4406990B..., both Valid). Run with the clone script (Loader.swift check included) and the harness copy. |
| `swift-only-proof.mjs` 0.1.0 vs 0.1.1 (Dell, `--repo clean2`, build logs = QA logs) | `ok: true`; changed payload = `appxmanifest.xml`, `sliceapp.exe` only; renderer digest equal and = pin. `log-swift-only-proof.txt` |
| App Installer feeds via `make-local-appinstaller.mjs` (RightKit 0.2.144, Mac) | `feed/SliceApp.0.appinstaller` 87d7e8cd..., `feed/SliceApp.1.appinstaller` 5eb70594...; Publisher equals the MSIX identity publisher. |

Signing certificate expires **2026-10-11 05:22:22 (Dell local, +05:30)**, about a day after this run. Installs of these packages keep validating (RFC3161 timestamp), but any new build needs a renewed certificate.

## Trust prerequisites in the guest

- Package signature: none. W02 observed `Valid` offline before anything was imported (`imported_public_cer: False`, `in_trusted_people: False`); the chain roots in the Windows root program. The harness imports the public `.cer` into TrustedPeople only when the status is not Valid; it did not.
- W12 only: `serve-local-feed.ps1` adds a self-signed `CN=localhost` certificate to the guest LocalMachine\Root store (disposable guest). Nothing else is imported.

## Environment deviation (required to run at all)

`<vGPU>Default</vGPU>` in `clean-machine.wsb.tmpl` makes the guest drop its RDP session about 16 to 30 s after connect ("connection lost", RDP disconnect reason 3; guest never logs on, zero receipts). Reproduced with a minimal .wsb on this Dell (attempts r5-final, r5-final-b, probes A). `<vGPU>Disable</vGPU>` works (probe B: LogonCommand ran after 6 s). All runs below use Disable (template sha256 59b27c11... to d7f11003..., in the patch). The guest therefore renders in software (display adapter "Microsoft Remote Display Adapter"); the runbook note that the Sandbox uses the desktop vGPU no longer holds on this machine. Also: the first `WindowsSandbox.exe` launch installed the Store Sandbox app; `wsb` is not on PATH; one Sandbox at a time, and a launch within seconds of a teardown fails with "failed to initialize".

## Results per check

Pinned harness = run `r5-final-c` (`receipts-r5-final-c/`, run.json sha256 4bc84ae4fe8bb26b714b8992845a80c96ff4d38f60d6f4e1443d332aa2df5625, guest-run.json bcd07263..., log `logs/log-sandbox-c.txt`). Patched harness = run `r5-patched8` (`receipts-r5-patched8/`, run.json f8c59997c129990eec9c6d7114d10a6192df0dbafdd8a0fb1820b87a67a5824e, guest harness sha256 2c73a6db..., log `logs/log-sandbox-p8.txt`). Earlier patched iterations are kept in `receipts-r5-patched`, `-patched2`, `-patched4`, `-patched5`, `-patched6`, `-patched7` (patched3 receipts were not pulled; runs 4 and 5 were stopped when W12 hung, so they have no run.json).

| Check | Pinned | Patched | Notes |
|---|---|---|---|
| W00 environment | PASS | PASS | elevated, 0 default routes, no adapters |
| W01 artifacts bound | PASS | PASS | old/new/cer/feed/scripts hashes = host manifest |
| W02 signer trust | PASS | PASS | Valid offline, no import |
| W03 install old (= plan "install") | PASS | PASS | 0.1.0.0 registered |
| W04 launch offline (= plan "offline launch") | FAIL | PASS | pinned: "no window within 40 s" (H1). Patched: window `SliceApp`; the running exe loaded `swiftright_render.dll` from `C:\Program Files\WindowsApps\OrthicLabs.SliceApp_0.1.0.0_x64__j3cejpx244dcr\` with no env var set (name-resolution half of F1 proven) |
| W05 write data | FAIL | PASS | pinned: cascade from W04/H2. Patched: marker in `%LOCALAPPDATA%\SliceApp\rows.json`, no `Packages\...\LocalCache` copy |
| W06 upgrade 0.1.0 to 0.1.1 (local msix) | FAIL | PASS | version 0.1.1.0, rows.json hash unchanged by install, old marker shown, new build wrote its own row |
| W07 corrupt update rejected | PASS (vacuous) | PASS | pinned refusal was 0x80073D02 "app in use", not corruption (H5). Patched: bit flipped inside `SliceApp.exe` (changed file) refused with **0x80080207 "computed hash of the block does not match the one stored in the block map"**, 0.1.0.0 stayed, genuine 0.1.1.0 then applied |
| W08 real interrupted update | FAIL | FAIL | NOT DEMONSTRATED (H7): interrupt cannot land in flight, so the run is invalid by design. Observations: exactly one version registered, status Ok, rows.json hash identical, build launches, rerun registers 0.1.1.0 |
| W09 rollback readable | FAIL | PASS | old build reads data written by the new build; schema 1 |
| W10 uninstall keeps data | FAIL | PASS | plain `Remove-AppxPackage`; rows.json byte-identical after removal, no LocalCache copy |
| W11 legacy data / physical path | FAIL | PASS | manifest: `FileSystemWriteVirtualization=disabled` + `unvirtualizedResources`; a rows.json written by a non-package process is read by the packaged app; the next edit lands in the same file; no LocalCache copy |
| W12 App Installer feed install + OnLaunch update | FAIL | FAIL | NOT DEMONSTRATED (H8). Publisher-mismatch rejection and the positive install both stall offline; the OnLaunch update was never reached. App Installer update route stays UNTESTED. Production host/TLS chain also UNTESTED |
| W13 installed renderer layout | FAIL | PASS | pinned: `LoadLibraryEx` of the WindowsApps DLL from a non-package process returns error 5 (H4). Patched: static check on the install location, Authenticode digest = pin (D8FB3B3B...), plus the W04 loaded-module path |
| W14 update deferred while running | FAIL | PASS | `-DeferRegistrationWhenPackagesAreInUse`: 0.1.0.0 stays registered while running, 0.1.1.0 after relaunch, data unchanged |

## Defects found

Harness (fixed in the patch unless noted):
- H1: UIA `ProcessId` is 0 for the packaged app's windows when read from the elevated guest, and the exe also opens a console window, so `Start-AppAndFindWindow`/`Get-AppRoot` never match. Patch: find the `Zed::Window` by class (probe `probes/P4-probe.txt`).
- H2: the row text fields are Edit controls with empty Name and AutomationId `row/<guid>/field`; the harness looked for Name `Row` (`probes/P7-probe.txt`).
- H3: `Remove-AppxPackage -PreserveApplicationData` fails with 0x80073CFA for a non-dev-mode package (breaks W08 to W12, W14). Data at the physical path survives a plain removal, which is what W09/W10 need.
- H4: W13's scrubbed `LoadLibraryEx` fails with error 5 on the WindowsApps copy (ACL shows Users RX) and with 182 on a Temp copy of the DLLs; neither is a product failure, the packaged exe loads the renderer fine (W04). The `-Mode Installed` closure test needs another mechanism or should stay the Stage-mode check.
- H5: the original W07 flipped a byte in `_FoundationICU.dll`, which is identical in 0.1.0 and 0.1.1. An update over the installed old build reuses unchanged blocks, so that flip is accepted and the installed file still hashes to the signed value (`receipts-r5-patched8/W07...json`, `info_unchanged_*`). It was also run with the app in use. Patched W07 tampers `SliceApp.exe`.
- H6: `interrupt-windows-install.ps1` `State()` printed a bare string into its return value (W08 "property 'when' not found"); `serve-local-feed.ps1` bound TLS only to 127.0.0.1 (`localhost` resolves to `::1` first), answered HEAD and Range requests with an exception that ended the server, and was single-threaded.
- H7 (not fixable here): AppXSvc's service host is protected (`taskkill /F` fails) and `Stop-Service` lets the deployment finish (job Completed, new version registered Ok). Triggering on the staging directory (instead of the slow event-log poll) made the stop land in flight (`stopped_in_flight: True`), still no failure. Needs another injection (for example a hard guest power-off with the data on a mapped folder).
- H8: with the feed fixed, App Installer fetches the .appinstaller (HEAD + Range) and Delivery Optimization sends one `Range: bytes=0-1` GET of the msix, then nothing (guest has no network profile). Probable cause: Delivery Optimization waiting for connectivity (not proven). A W12 run needs a guest with a network adapter, which conflicts with the offline W00/W04 premise, or another feed mechanism.
- The pinned W12 and W13 can never pass as written; the pinned run also lacks per-step timeouts around `-AppInstallerFile` (hangs without the patch).

Product:
- P1: `SliceApp.exe` is a console-subsystem executable: the packaged launch shows a `ConsoleWindowClass` window (title = exe path) beside the app window. Not covered by any check.

## Not tested / limits

- Production App Installer host and TLS chain; the OnLaunch update path (W12).
- A truly interrupted deployment (W08). The AppXSvc stop is fault injection, not a Microsoft procedure, and did not interrupt anything here.
- Hardware GPU in the guest (software rendering only, see environment deviation).
- The patched results are patched-harness evidence (guest harness sha256 2c73a6db2db42be976a99a4a2188b359d0caa19920c73fa8c1bc7956a0203049), not the pinned harness.

## Files

`inputs/` (msix, seals, QA logs), `qa-receipts/`, `feed/`, `log-host-verify.txt`, `log-swift-only-proof.txt`, `log-appinstaller-gen.txt`, `receipts-r5-*/`, `staging-manifests/`, `logs/` (Sandbox host logs, launch scripts), `probes/` (diagnostic guest probes and outputs, not harness evidence), `harness-patched/` (patched scripts and unified diffs). Patch in the working tree: `examples/SliceApp/RESULT-R5-harness.patch` (sha256 d6897a4f4a5ed6f792981d9f0d8821da7398a22fc48394236441b42185066812; `git apply --check` clean at 54d480c). Dell working files remain in `D:\Claude\sr0-r5` (clones, `runs\`, `probe\`); nothing outside it was touched.
