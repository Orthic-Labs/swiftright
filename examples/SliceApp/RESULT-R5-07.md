# R5-07: SliceApp MSIX pair rebuilt on the SR0 tuple 07 renderer (build part, 2026-10-10)

Scope: build, sign and verify only. No Windows Sandbox, no upload, no publication. The Sandbox round (R5-07 W-checks) is pending the lead's "GO sandbox". Host: Dell (Bogus-Dell), stage root `D:\Claude\sr0-r5-07` (kept for the Sandbox run). Both builds ran as the non-elevated one-shot Interactive/Limited task (`elevated=False` first line of each log), @rightkit/release 0.2.145, Swift 6.4 toolchain.

**Result: both packages built, signed, sealed and verified. Nothing failed.**

## Renderer pin (commit 850fa66)

| Field | Value |
|---|---|
| Renderer | `D:\Claude\sr0-r07\renderer\swiftright_render.dll`, 11,882,496 B, RightKit-built from 02b3cc0, unsigned |
| sha256 (raw) | `97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B` |
| Authenticode digest (PeDigest.Sha256) | `531F1093BFF83E25139AAF8FF5C991ABC39AE800525DD21C4A7CE91C0C4F5163` (the same routine returns the old pin `D8FB3B3B…` on the old DLL) |
| Import set | identical to the previous renderer (`dumpbin /dependents`); pin `closure` unchanged |
| `renderer-pin.json` sha256 in both clones | `4e6fa275ca8fb3b37dd6aea1a7e7ff78e195afce4a111964d761cb1e3ba639a9` |
| Build log lines | `renderer pinned ok: renderer source sha256=97CA28E8…` and `renderer copy sha256=97CA28E8…` in both logs |

## Builds

| | 0.1.0.0 | 0.1.1.0 |
|---|---|---|
| Clone | `D:\Claude\sr0-r5-07\clean` | `D:\Claude\sr0-r5-07\clean2` |
| Source | `850fa66ce3805655c36032f085b7e0326072cdbc` (origin https://github.com/bogusyogi/swiftright, `git checkout -B master 850fa66`, clean tree) | clone-local commit `54480b6dbfe540804d0d269a9b2f60ad9955b9af` on top of 850fa66 (`bump-version-win.ps1` 0.1.0 to 0.1.1: package.json, swift-package.json x2, right-release.config.mjs x2, SliceApp.manifest, one Swift diagnostic string in `WindowsBootstrap.swift`; 5 files, 7 insertions, 7 deletions; not pushed) |
| Tree | 00533c4bfa287ca7b17526e774026a0ee95c44bb | da58ae0e3fc27b782ce5d9cd32aa81ddc721cfd6 |
| QA source receipt (`right-release qa --stage source --platform win`, runner `D:\Claude\sr0-r5\bin\rightkit-qa.exe` sha256 fa6c73e6e856…7260) | digest `30ff05406b11373afe9b0c10b06b9690005c49ebcf021a787e0fbb407507e676`; app.build, app.launch (smoke.launch), journey.restart-keeps-data all passed (3 passed, 0 failed) | digest `0cdf48afdda913849ebf1f4602347533e23fc115ec76347fb5c8b46e35458c38`; same three checks passed |
| Seal / release id | `sliceapp-0.1.0-850fa66c` | `sliceapp-0.1.1-54480b6d` |
| `SliceApp_x.msix` | `SliceApp_0.1.0.0_x64.msix`, 29,048,110 B, sha256 `c1f12ee25c6e9e0341f0dd752cff22cdd1e892b1855176a5ff1fcd893c8503b6` | `SliceApp_0.1.1.0_x64.msix`, 29,048,398 B, sha256 `c1863d4c35f053ae256c6341d65dedd7960494fc5d66a914bdcd76fb50979d60` |
| Equals seal `msix.sha256` | yes | yes |
| `msix-seal.json` sha256 | 4622a324159e19d14d68b6661728b3fe32df5978da89c08b3109819de51d7b6a | 6c261a78cf110e64dc7ecfb49ffd113d89641c40175e128b7dc7474e040f6202 |
| `release-manifest.json` sha256 | 05b33d6ca356fde59982284c5626dabf649030cdd20ce73989e7933d1f61ccf5 | b487255f3826e0ff2fea9da1e2db65b607bd2c0f0d3d4f1e87947c938325609d |
| Build time (right-release `done`) | 87.9 s | 80.9 s |
| hardeningscan | clean | clean |
| Seal location (Dell) | `clean\.right-release\sealed\sliceapp-0.1.0-850fa66c\windows` (state: `...\state\...\msix-seal.json`) | `clean2\.right-release\sealed\sliceapp-0.1.1-54480b6d\windows` |

Sequence per clone: `pnpm install --frozen-lockfile`, (0.1.0 only) `right-release doctor --platform win`, `right-release qa --stage source --platform win`, `right-release build --platform win`, all through `D:\Claude\sr0-r5-07\step-r507.ps1` / `run-unelevated-step.ps1`. QA opened SliceApp windows on the Dell desktop (UIA, window-targeted). No version was refused as already sealed (fresh clones). The Mac copies of the msix hash identically (`shasum -a 256`).

## Verification

| Check | 0.1.0.0 | 0.1.1.0 |
|---|---|---|
| `signtool verify /pa /v` (Windows Kits 10.0.26100.0) | Successfully verified, exit 0, 0 warnings, 0 errors | same |
| Signer / chain | Damned Ventures LLC, SHA1 121FD7B569E256DA0AF63B1BF8E3CD5AEDF888D3, leaf expires 2026-10-12 05:16:54 (Dell local); chain Microsoft Identity Verification Root CA 2020 > ID Verified Code Signing PCA 2021 > ID Verified CS AOC CA 03 > leaf | same |
| RFC3161 timestamp | 2026-10-10 10:20:34, Microsoft Public RSA Time Stamping Authority | 2026-10-10 10:23:12, same chain |
| `Get-AuthenticodeSignature` | Valid | Valid |
| Package unpacked (`makeappx unpack`, 27 files) | `D:\Claude\sr0-r5-07\unpack\0.1.0` | `...\unpack\0.1.1` |
| `verify-package-layout.ps1 -Mode Stage` on the unpacked signed payload | OK: renderer beside SliceApp.exe, Authenticode digest = pin 531F1093…, ABI 0.6, shipped closure present | OK |
| Same check on the clone's `.build\msix-stage` (pre-sign stage dir) | OK | OK |
| PE subsystem of SliceApp.exe (Subsystem field read from the packaged exe) | 2 (GUI) | 2 (GUI) |
| Stage-time subsystem gate (0.2.145) | `swift-package.json` declares `"subsystem": "gui"`; `swift-windows-stage.mjs` of the installed 0.2.145 contains `SWIFT_STAGE_SUBSYSTEM`; `swift-package windows-stage` exited 0 in the build (the log has no dedicated gate line; the negative control is in PACKAGING.md) | same |
| Every PE in the package (exe + 19 dlls) | all `Valid` | all `Valid` |
| Signed renderer, raw sha256 in the package | `1497699ef4d10c2dc4646277739b8f83639685f2a3fbfba1b6d94c671e27b408` (11,897,296 B) | `5aefa229cd8f38acddd4b5453b8b717c1a82c3c19110fe604aa7235caabfdc10` |
| Tree after build | clean (`.right-release/` excluded) | clean |

`swift-only-proof.mjs` (0.1.0 vs 0.1.1, `--repo clean2`, both seals, both logs as build logs, both msix): `ok: true`, no failures. Changed payload = `appxmanifest.xml` and `sliceapp.exe` only; renderer sha256 and Authenticode digest equal and equal to the pin; changed sources = the 5 bump files; the logs mention no Rust compile.

App Installer feeds: `SliceApp.appinstaller` in each `dist\win` is the build's own placeholder-URL file; the Sandbox feeds are regenerated below (build part: not done yet).

## Notes and limits

- The signing certificate (thumbprint 121FD7B5…) is valid today and expires 2026-10-12 05:16:54 Dell local. Installs keep validating through the RFC3161 timestamp; any later build needs a renewed certificate.
- The signing worked on first attempt (Artifact Signing via RightKit); no cert issue. The cert is not in the local Windows cert stores (cloud signing), so validity was read from the signtool chain.
- The QA runner used is the R5 build of `rightkit-qa.exe` (`D:\Claude\sr0-r5\bin`); the receipt binds its hash (above).
- The clone-local 0.1.1 commit exists only in `D:\Claude\sr0-r5-07\clean2` (not pushed).
- Not done in the build part (by scope): Windows Sandbox checks W00 to W14 (see "Sandbox results" below), any upload.

## Files

Mac: `/Volumes/D/sr0-artifacts/win/r5-07/` — `inputs/` (both msix, seals, release manifests, QA/build logs), `qa-receipts/` (both source receipts), `log-host-verify.txt`, `log-swift-only-proof.txt`.
Dell (`D:\Claude\sr0-r5-07`, kept): `clean`, `clean2`, `unpack\0.1.0`, `unpack\0.1.1`, `log-r507-0.1.0.txt`, `log-r507-0.1.1.txt`, `step-r507.ps1`, `verify-r507.ps1`, `proof-r507.ps1`, `pedigest.ps1`, `deps.ps1`, `run-unelevated-step.ps1`.

## Sandbox results (2026-10-10, after "GO sandbox")

Host and guest as in RESULT-R5.md final2: Dell (Bogus-Dell, Windows 11 24H2 build 26100.9550), Windows Sandbox guest OS 10.0.26100.9550, `<vGPU>Disable</vGPU>` (software rendering), same `.wsb` template, same harness. Harness tree = `git archive 61b8698` of `qualification/clean-machine/windows`, `examples/SliceApp/scripts`, `Windows/renderer-pin.json` (staged at `D:\Claude\sr0-r5-07\harness`, tar sha256 `0104d57e…ea1b`). `run-sandbox.ps1` (host, `c3305a70…e4aa`), `sandbox-run.ps1` (guest, `42d09553…aa42`), `interrupt-windows-install.ps1` and the `.wsb` template are byte-identical to the final2 copies; the only harness-side difference is `verify-package-layout.ps1` (no PE subsystem check any more: it moved to the 0.2.145 stage gate; W04 still reads the subsystem and counts console windows in the guest). Both msix hashes were checked against the seals by the host (`-ExpectOldSha256 c1f12ee2…`, `-ExpectNewSha256 c1863d4c…`). App Installer feeds regenerated with `make-local-appinstaller.mjs` (RightKit 0.2.145): `SliceApp.0.appinstaller` 87d7e8cd…04c6 and `SliceApp.1.appinstaller` 5eb70594…1570, byte-identical to the final2 feeds (they depend only on identity and version).

| Run | Profile | Launch | Checks | run.json sha256 | Result |
|---|---|---|---|---|---|
| `r5-07-offline-2` | Offline (W00: 0 default routes) | non-elevated one-shot task (`elevated=False`), as in final2 | W00 to W11, W13, W14 | `a61a73a233346c3b5e556270ab687c5dfe6339387a7f3b41a3c98425bfb744d4` | 13 of 14 PASS, **W08 FAIL (perturbed, see below)** |
| `r5-07-network-2` | Network (W00: 1 default route) | non-elevated one-shot task | W00, W01, W12 | `89b1581a66261172da816830dd34cac22dbe8d830b3f37090e030883443171df` | 3 of 3 PASS |
| `r5-07-offline` (iteration 1, kept as evidence, not in the qualification records) | Offline | **launch slip**: `-Cmd ''& script''` through `win` and `sh` lost its quotes (the gotcha in R5-RUNBOOK.md), so PowerShell 7 ran the launcher as a background job in the SSH admin session instead of the non-elevated task | W00 to W11, W13, W14 | `36d656ca039551c2142ba2bd7edd6690433517f9006d7644f9fafa8d970fa2d3` | 14 of 14 PASS, **W08 PASS** (5 genuine interruptions, all judged ok, none NeedsRemediation) |

Iteration 1 was repeated through the non-elevated task (`r5-07-offline-2`) to match final2. Artifacts and logs: `/Volumes/D/sr0-artifacts/win/r5-07/` (`receipts-offline-1`, `receipts-offline-2`, `receipts-network-2`, `logs/`); Dell: `D:\Claude\sr0-r5-07\runs\<run id>`.

### Per-check results

| Check | Offline-2 / Network-2 | Notes |
|---|---|---|
| W00 environment | PASS / PASS | offline: 0 default routes; network: 1 default route; guest elevated |
| W01 artifacts bound | PASS / PASS | old, new, cer, feed, scripts hashes = host manifest |
| W02 signer trust | PASS | `Valid` offline with the public .cer only, no import |
| W03 install old (0.1.0.0) | PASS | registered |
| W04 launch offline | PASS | window `SliceApp`; PE subsystem 2; 0 console windows; log banner for the running pid; renderer loaded from the package directory; 0 default routes |
| W05 write data | PASS | marker in `%LOCALAPPDATA%\SliceApp\rows.json`, no `Packages\...\LocalCache` copy |
| W06 upgrade 0.1.0 to 0.1.1 | PASS | rows.json hash unchanged by the install; marker shown; new build wrote its own row |
| W07 corrupt update rejected | PASS | bit flipped in `SliceApp.exe`, refused with 0x80080207 (block hash mismatch), 0.1.0.0 stayed, genuine 0.1.1.0 then applied |
| **W08 interrupted update** | **FAIL (perturbed)** | 11 cases: 2 KillClient (client alive, deployment completed anyway), 9 CancelOperation, 6 genuine interruptions; 3 judged ok (c3 staging+0, c4 +160, c11 start+0), 3 bad (c5 +200 ms, c9 +320 ms, c10 +360 ms): see below |
| W09 rollback readable | PASS | old build reads data written by the new one; schema 1 |
| W10 uninstall keeps data | PASS | rows.json byte-identical after removal (sha `2915c7e4…`), no LocalCache copy |
| W11 legacy data / physical path | PASS | manifest `FileSystemWriteVirtualization=disabled` + `unvirtualizedResources`; legacy rows.json read and edited in place |
| W12 App Installer feed install + OnLaunch update | PASS (network) | publisher-mismatch feed rejected (0x8008020C), nothing installed; correct 0.1.0.0 feed installs; swapping to the 0.1.1.0 feed and relaunching (`OnLaunch HoursBetweenUpdateChecks=0`) registers 0.1.1.0; rows.json hash unchanged. Production App Installer host and TLS chain remain untested |
| W13 installed renderer layout | PASS | Authenticode digest = pin `531F1093…` (signed copy raw sha256 `1497699e…`), exe and dll `Valid` |
| W14 update deferred while running | PASS | 0.1.0.0 stays while running, 0.1.1.0 after relaunch, data unchanged |

### W08 in `r5-07-offline-2` is perturbed by a manual Repair

Not a clean W08 verdict. During this run's W08 a person (Adrian) saw the shell dialog "Can't open this app ... Advanced options ... Repair" in the Sandbox guest and clicked Repair (Settings > Advanced options > Repair). That was a manual action on the guest, not the harness. The records are kept unmodified; `qualification/receipts/package/win-r5-07-offline/NOTE-W08-perturbed.txt` marks the run.

What the records show (per-case evidence `evidence-W08-c*.json`, written by the guest at the interrupt, so they contain nothing after it):
- c5, c9, c10 were genuine cancels (`CancelOperation` at staging+200/+320/+360 ms) that failed to reach `RegistrationChanged` (error 0x80073CF8, event 751 "Windows failed to undo changes ... The package needs to be reinstalled"). 0.1.0.0 was left registered as `Modified, NeedsRemediation`, data byte-identical (`2915c7e4…`), the 40 s launch wait found no window; the second `Add-AppxPackage` then registered 0.1.1.0 with status Ok, data intact, in all three.
- Wall-clock gaps between consecutive evidence files (host mtime): c5 10:57:05 to c6 10:58:04 (59 s), c9 10:58:48 to c10 10:59:49 (61 s), c10 to c11 11:00:48 (59 s), against 15 to 20 s for a normal judged case: each bad case spent the full 40 s launch wait. The dialog the person saw is presumably the shell's reaction to that launch attempt on a NeedsRemediation package (inferred, not recorded).
- Which of c5, c9, c10 the Repair landed in is not recorded (no time stamp of the click). The three failed launches (`launched=false`) and the three recoveries are indistinguishable by their outputs.
- Iteration 1 (`r5-07-offline`, no perturbation reported) had no NeedsRemediation case at all, so the outcome is timing dependent, as in RESULT-R5.md (final2: 1 of 5 genuine interruptions; the phase window is a few hundred ms).
- The harness-side judgment is unchanged: a genuine cancel in the registration phase can leave the previous version unlaunchable until the update is re-applied (the documented recovery); data was never touched.

### Settings > Repair data point (same version), as requested by RightKit

Not obtained. The guest was gone by the time the request arrived: the harness ended it with `Stop-Computer` after W11 (guest-run.json 11:01:40, host run.json 11:01:45; `WindowsSandboxServer` gone at 11:02), and Sandbox state is discarded on close. Nothing was recorded for the state right after the Repair (Get-AppxPackage status/version, UIA window plus log banner, rows.json and marker, AppXDeploymentServer events around the click). What the run does show after W08, in the same guest: the final registered version is 0.1.1.0 Ok after each case; W14, W09 and W10 pass on the same data (`2915c7e4…`, unchanged) and W11 passes on its own legacy file, so the later checks were not disturbed. If the data point is still wanted, it needs a deliberate run: provoke a NeedsRemediation state (a CancelOperation at about +200 ms, reproducible in 3 of 6 genuine interruptions here), click Settings > Advanced options > Repair, and capture the items above before the guest closes (the harness would need a hold-open step; the guest currently powers off at the end).

### Package stage check

`python3 -I qualification/run.py run --stages package --no-tuple` (builds and outputs under the scratchpad) with the two run directories in `qualification/receipts/package/` (`win-r5-07-offline` = r5-07-offline-2, `win-r5-07-network` = r5-07-network-2): both parse and validate under `sr0-a.package-receipt/v2`. `win-r5-07-network`: windows-x64 3/3 PASS (old msix `c1f12ee2…`, new msix `c1863d4c…`, signer cer `d063ba1a…`). `win-r5-07-offline`: fails only on `W08-interrupted-update` (run status fail, check status fail, implemented true); the windows-x64 union therefore fails with "W08: no implemented passing record (win-r5-07-offline: fail)". The macOS union still passes (12/12, unpinned). No tuple comparison was made (`--no-tuple`; tuple-final.json still names the old MSIX).

### Limits

- The run used software rendering (vGPU Disable); hardware-GPU rendering in the guest is not covered. The production App Installer host and TLS chain are untested (W12 used a guest-local self-signed feed).
- W08 is a known platform limitation (MSIX deployment cancelled in the registration phase); the offline-2 verdict is perturbed by the manual Repair and is not a clean result either way.
- The extra stage-time dry run `r5-07-dry` and the `unpack\` directories remain on the Dell under `D:\Claude\sr0-r5-07` (kept until the lead says).
