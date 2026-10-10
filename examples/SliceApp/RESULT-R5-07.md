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

App Installer feeds were not regenerated here (`SliceApp.appinstaller` in each `dist\win` is the build's own placeholder-URL file; the Sandbox feeds come from `make-local-appinstaller.mjs`, which depends only on identity and version, so the R5 feeds in `/Volumes/D/sr0-artifacts/win/r5-final2/feed/` are unchanged).

## Notes and limits

- The signing certificate (thumbprint 121FD7B5…) is valid today and expires 2026-10-12 05:16:54 Dell local. Installs keep validating through the RFC3161 timestamp; any later build needs a renewed certificate.
- The signing worked on first attempt (Artifact Signing via RightKit); no cert issue. The cert is not in the local Windows cert stores (cloud signing), so validity was read from the signtool chain.
- The QA runner used is the R5 build of `rightkit-qa.exe` (`D:\Claude\sr0-r5\bin`); the receipt binds its hash (above).
- The clone-local 0.1.1 commit exists only in `D:\Claude\sr0-r5-07\clean2` (not pushed).
- Not done (by scope): Windows Sandbox checks W00 to W14, App Installer feed generation, any upload.

## Files

Mac: `/Volumes/D/sr0-artifacts/win/r5-07/` — `inputs/` (both msix, seals, release manifests, QA/build logs), `qa-receipts/` (both source receipts), `log-host-verify.txt`, `log-swift-only-proof.txt`.
Dell (`D:\Claude\sr0-r5-07`, kept): `clean`, `clean2`, `unpack\0.1.0`, `unpack\0.1.1`, `log-r507-0.1.0.txt`, `log-r507-0.1.1.txt`, `step-r507.ps1`, `verify-r507.ps1`, `proof-r507.ps1`, `pedigest.ps1`, `deps.ps1`, `run-unelevated-step.ps1`.
