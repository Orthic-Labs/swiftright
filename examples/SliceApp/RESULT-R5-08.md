# R5-08: SliceApp MSIX pair on SR0 tuple 08 (renderer E280F4A9), build and Sandbox (2026-10-10)

Dell stage root `D:\Claude\sr0-r5-08` (nothing deleted or recycled; every directory is left in place). @rightkit/release 0.2.146, non-elevated one-shot tasks (`elevated=False`), harness = `git archive` of HEAD 840f9ec (hold-open harness from a6d657b, unchanged since). Artifacts: `/Volumes/D/sr0-artifacts/win/r5-08/`.

## Build (pin: sha256 `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93`, Authenticode digest `E713BF40…9B0E`)

| | 0.1.0.0 | 0.1.1.0 |
|---|---|---|
| Source | `a6d657bd1dd3491c33b80264d7ae52aeb5409877` (clone `clean`, branch master, clean tree) | clone-local `5e6338b6a29872a5f1b3cd3f08ede94b5a543e26` on a6d657b (`bump-version-win.ps1`, clone `clean2`, not pushed) |
| QA source receipt | passed `75b1db2fc9b0d37b…` (app.build, app.launch, journey.restart-keeps-data) | passed `53b8a4b096faca61…` (same three) |
| Seal | `sliceapp-0.1.0-a6d657bd` | `sliceapp-0.1.1-5e6338b6` |
| msix sha256 | `c80c694735754f7bff892a74e2335c2d8cd7a87e8555f2e5233bd47392a7a0c4` (29,048,439 B) | `0ff6516543d2c2dec49dd41a65ae3ef0a7eb9c7d34f9c05321534f731b6bc8e8` (29,048,713 B) |
| = seal msix.sha256 | yes | yes |
| signtool verify /pa | Successfully verified, 0 errors; Damned Ventures LLC 121FD7B5… (expires 2026-10-12 05:16:54) | same |
| verify-package-layout Stage (unpacked signed payload and `.build\msix-stage`) | OK, digest = pin | OK |
| SliceApp.exe PE subsystem | 2 | 2 |
| Signed renderer raw sha256 | `95497791…f40b` | `75e3e531…4cc4` |

`renderer pinned ok` (source and copy) in both logs. `swift-only-proof.mjs`: `ok: true`, changed payload `appxmanifest.xml` and `sliceapp.exe` only. Feeds regenerated: byte-identical to tuple 07 (`87d7e8cd…`, `5eb70594…`). Seal sha256: `b49e6c28…` / `822379bf…`.

## Sandbox

| Run | Profile | Result | run.json sha256 |
|---|---|---|---|
| `r5-08-offline` (`-HoldOpenForRepairMinutes 10`) | Offline | 13 of 14 PASS, **W08 FAIL** | `36f50858cdea64ed323d56660f1fde24f5378a91cce0853f24edf0eb67115fa8` |
| `r5-08-network` | Network | W00, W01, W12 PASS | `4627ee1d62a3a196140d3d8f454ef8958ab1bd7197858e44baeae5ed1cbcae38` |

Offline: W00 to W07, W09 to W11, W13, W14 PASS; W12 PASS (network run). W08: 11 cases, 6 genuine interruptions, 4 judged ok (c3, c4, c5, c11), 2 bad: c6 (+240 ms) and c7 (+280 ms) left 0.1.0.0 `Modified, NeedsRemediation` (failed to reach RegistrationChanged), no window within 40 s; the second update then registered 0.1.1.0 Ok with data intact (rows sha unchanged). The harness's own verdict; nothing perturbed it by a person that is recorded.

### Hold-open data (W08, case c6)

- Guest held 13:12:25 to 13:22:26 Dell local; log `hold-open-W08.log` has the "awaiting manual Repair" line (13:12:25, package 0.1.0.0 status `Modified, NeedsRemediation`).
- **No manual Repair happened**: package state never changed during the hold (`hold_open_state_changed=False`, no AppXDeploymentServer events between hold start and end), so there is no post-Repair data.
- At hold end the end-of-hold snapshot recorded status `Modified, NeedsRemediation`, version 0.1.0.0, rows sha unchanged. Its launch attempt (explorer AppsFolder) failed ("no window within 40 s") and, at 13:22:26.9, the deployment service ran a `RegisterByPackageFullName` operation on 0.1.0.0 ("Trying to repair ACLs" then "ACLs repaired successfully", Register finished successfully, 13:22:27.1). That is a platform-initiated register triggered at the launch attempt, not a person; the state after it was not captured (the snapshot's status was read before the launch). The case then continued to the normal second update.
- Window titles in the copied records: only the test app's `SliceApp`; no user window titles.

## Package stage

`run.py run --stages package --no-tuple` parses `win-r5-08-offline` and `win-r5-08-network` (network 3/3 PASS; offline fails only on W08). The union with the existing win-r5-07 directories fails on artifact identity (different tuple msix), as expected; pass only the r5-08 directories for a tuple 08 evaluation. `tuple-final.json` was not compared.
