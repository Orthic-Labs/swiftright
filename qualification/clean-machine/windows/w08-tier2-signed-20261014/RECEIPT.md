# W08 Tier 2 guard on the release-signed pair, CI run 38535084834 (2026-10-14)

Result: package smoke PASS; guard negative controls that need one package PASS; DMG read-only checks PASS; **positive repair (cancelled update to NeedsRemediation, then guard repair) NOT RUN: BLOCKED**, because the run signs one MSIX only (0.1.0.0) and an update needs a newer release-signed version. W08 is not closed by this receipt.

## Inputs (downloaded with `gh run download 38535084834` into `/Volumes/D/sr0-artifacts/tuple12-signed/run-38535084834/`)
- Run 38535084834, source `5d471f40966a10f675b6d8199da7e285b2943e52`, publish=false (windows-sign, macos-sign, installed-qualification green).
- `SliceApp_0.1.0.0_x64.msix` sha256 `2ef9dc7b6f89000bf9a01ff58e318e4a55fe91cf80f037dfec95c29e66a74050` (verified, also after copy to the Dell). Signer `CN=Damned Ventures LLC` (valid, Microsoft Public RSA timestamp). Unsigned candidate `003e217e...bcbd5` (finalize-evidence.json).
- `SliceApp_0.1.0_arm64.dmg` sha256 `9698efc56a137bd83e29a17790c3e92f6d38d75acad8f1130a90f18a306f0be4` (verified; differs from the unsigned candidate DMG `2dd9e018...`).
- Guard pin `packages/SwiftRightBridge/guard/rightkit-pin.json`: RightKit commit `07081ba870b82fa01e6c6342a94bf2be99c2bb1b`, package 0.2.153, guard v2, sha256 `3df2415f19db8dfaffad1714b105434236310f9e84e10616855f96ae58cf634b` (file with its final LF). The app writes the embedded source without the final LF, so the deployed file hashes to `b116809eed59983e0f126308e5a2181c9fce1fdef98816fc99f455accc9c1b34` = the pinned file minus its last byte (checked on the Mac). `guard_matches_pin:false` in signed-guest.json is that expected one-byte difference, not drift.

## Procedure
Long-lived minimised Windows Sandbox worker (`factory/tools/sandbox/client.py`), software rendering, Windows 10.0.26100. Job kind `command` running `signed-guest.ps1` (this folder). No certificate was imported: the MSIX installed on the platform's own trust (TrustedPeople has no signer entry). Nothing ran on the Dell desktop. The Sandbox had exited at 14:14 IST (no job of ours; no cause found in the System log) and was restarted once with `client.py start` (minimised, all windows iconic, 0 foreground samples); the job then ran.

## Results (`signed-guest.json`)
| Check | Result |
|---|---|
| Add-AppxPackage of the signed MSIX | OK, 1.8 s, `OrthicLabs.SliceApp_0.1.0.0_x64__j3cejpx244dcr`, status Ok, publisher Damned Ventures LLC |
| Packaged launch (shell:AppsFolder) | window `SliceApp` 653 x 515 visible, 21581 distinct sampled colours, black fraction 0.013 (`packaged-window.png`), WM_CLOSE exit within 20 s, no crash events |
| Guard registration by the packaged launch | task `OrthicLabs.SliceApp_j3cejpx244dcr-Repair` registered 2.1 s after launch, triggers event (751) + logon, per-user Interactive/Limited, guard.json v2 |
| Healthy package (negative control) | task run: `last-result` healthy code 0 "package healthy: 0.1.0.0:Ok", package full name and status unchanged, no Add-AppxPackage logged: PASS |
| Task deleted | next launch re-registered it in 4.6 s: PASS |
| Uninstall | after Remove-AppxPackage the task and `%LOCALAPPDATA%\SliceApp\repair` were removed 15.9 s after the task was started (logon stand-in); `rows.json` kept with identical sha256 `40b2a634...2cf`: PASS |
| Positive repair, repair time | NOT RUN (blocked, see top). Reference from the earlier self-signed test pair (`../w08-tier2-sandbox-20261013`): cancel to Ok 12.8 to 14.0 s |
| Other negative controls (wrong identity, stale feed, corrupt package, feed down, mutex, kill-client) | not rerun: all need an old to new update. Earlier results stand for the test pair only |

## Mac DMG (`dmg-check.txt`)
hdiutil verify VALID; spctl accepted (Notarized Developer ID, Adrian D'souza 6KLGD3LLKF); codesign valid; stapler validate worked for the DMG and the mounted SliceApp.app; app not launched.

## To unblock the positive case
A second `release-candidate` run with `version` 0.1.1 and `signed_qualification` true (publish false) yields a release-signed 0.1.1.0 MSIX; the existing harness (`client.py w08 tier2-repair --pkg-dir <dir with old.msix, new.msix>`) then runs unchanged apart from the feed publisher string in `.work/w08t2/feedin/*.appinstaller`. That dispatch uses the signing service and was not authorized here, so it was not started.
