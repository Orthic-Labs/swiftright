# W08 Tier 2 guard on the release-signed pair (2026-10-14)

Result: **positive repair PASS (2 of 3 induced runs; the third never induced NeedsRemediation), update-based negative controls PASS, single-package controls PASS, DMG read-only checks PASS.** Old = release-signed 0.1.0.0 from run 38535084834, new = release-signed 0.1.1.0 from run 38538717695. This is Sandbox evidence for the guard on release-signed bytes, not independent review; Oracle/owner closure of W08 is separate.

## Inputs
- Old: run 38535084834 (source `5d471f40966a10f675b6d8199da7e285b2943e52`), `SliceApp_0.1.0.0_x64.msix` sha256 `2ef9dc7b6f89000bf9a01ff58e318e4a55fe91cf80f037dfec95c29e66a74050`; DMG `9698efc56a137bd83e29a17790c3e92f6d38d75acad8f1130a90f18a306f0be4`. Signer `CN=Damned Ventures LLC`, valid, Microsoft Public RSA timestamp.
- New: run 38538717695 (`release-candidate`, version 0.1.1, source `576349418c00694f67e3e6c8eb94a1c18396aafd`, signed_qualification=true, publish=false; all jobs green, publish skipped), `SliceApp_0.1.1.0_x64.msix` sha256 `20633b304c626d2b8cbd379b46af8478a993ad88214447ceb03baf9fb61ff9bb`, same signer. Downloaded to `/Volumes/D/sr0-artifacts/tuple12-signed/run-38538717695/`.
- Why a bump commit on master: `scripts/release/candidate.mjs admit` requires the source to be an ancestor of origin/master and `version == examples/SliceApp/package.json`, and the release scripts hard-code `0.1.0`. A branch-only dry run fails the ancestor check. So `576349418` (package.json, swift-package.json, right-release.config.mjs, SliceApp.manifest, the three scripts under scripts/release: 0.1.0 to 0.1.1) was pushed, the run was dispatched pinned to that SHA, and `e782338a4` reverted it straight away. Master is back to 0.1.0; the signed 0.1.1.0 bytes exist only as CI artifacts (not published). No Swift change between old and new: the pair differs by version fields, so the update path is exercised, not a code change.
- Guard pin `packages/SwiftRightBridge/guard/rightkit-pin.json`: RightKit `07081ba870b82fa01e6c6342a94bf2be99c2bb1b`, 0.2.153, guard v2, sha256 `3df2415f19db8dfaffad1714b105434236310f9e84e10616855f96ae58cf634b` (file with final LF). The app writes the source without the final LF; the deployed file hashes to `b116809eed59983e0f126308e5a2181c9fce1fdef98816fc99f455accc9c1b34` (= pinned file minus last byte, checked on the Mac). Both packages embed the same guard.

## Procedure
Long-lived minimised Windows Sandbox worker, software rendering, Windows 10.0.26100; `client.py w08 <method> --pkg-dir pkgs-signed` with the unmodified harness (`guest_sha256_original` `8c2bd58b...c555`, only `Stop-Computer` patched by the job). Packages staged at `.work/w08t2/pkgs-signed` (old.msix, new.msix, extra/). The feed `.appinstaller` files use Publisher `CN=Damned Ventures LLC, O=Damned Ventures LLC, L=new york, S=New York, C=US` (originals kept in `.work/w08t2/feedin-selftest` and restored afterwards). Negative-control inputs: `wrongid.msix` and its feed reused from the self-signed test set (identity `OrthicLabs.OtherApp`); corrupt-old/new are the signed MSIX truncated to 60 percent. Harness trusts the public signer cert in the Sandbox only. The guard is never started by hand except in `uninst` (logon stand-in). Nothing ran on the Dell desktop.

## Positive repair and negative controls (per-run evidence in the subfolders)
| Run | Induced (delay ms, attempts) | Outcome | Seconds cancel to Ok |
|---|---|---|---|
| r360-a repair | NO: 8/8 completed-anyway at 360 | harness induction failure (`induction did not reach NeedsRemediation`), not a guard result; same behaviour as the earlier self-signed r240/r300 runs | n/a |
| r360-b repair | yes (360, 1st) | repaired to 0.1.1.0 Ok, launch OK, data sha equal | **12.6** |
| r400-a repair | yes (330, 4th) | repaired to 0.1.1.0 Ok, launch OK, data sha equal | **14.1** |
| healthy | none | guard did nothing: status healthy, package unchanged, no Add-AppxPackage logged | n/a |
| taskdel | none | task deleted, re-registered by the next launch in 5.5 s; with a fresh install-attempt marker it was NOT re-registered and `install skipped` was logged | n/a |
| uninst | none | task and repair folder removed, user data kept | n/a |
| wrongid | yes (360, 1st) | feed and msix both `REFUSED ... Name OrthicLabs.OtherApp differs from OrthicLabs.SliceApp`, nothing installed; after the good feed returned the retry repaired it to 0.1.1.0 Ok | 145.3 |
| stale | yes (330, 2nd) | feed serving only 0.1.0.0: recovered to 0.1.0.0 Ok, no downgrade refusal | 12.9 |
| corrupt | yes (360, 1st) | corrupt msix refused, explicit failure, package untouched until good files returned; retry repaired to 0.1.1.0 Ok | 147.8 |
| mutex | yes (330, 2nd) | second run logged `another repair run is active`; one repair, 0.1.1.0 Ok | 26.1 |
| feed-down fd-a | yes (300, 4th) | explicit `feed unreachable` failure, retry scheduled, package untouched; feed back, retry repaired it with no manual start, 0.1.1.0 Ok | 153.3 |
| uninst-retry | yes (360, 1st) | first run failed with the feed down and scheduled a retry; after Remove-AppxPackage the retry tick alone removed task and folder 137.6 s later; user data kept | n/a |
| kill-client | NO: 12/12 completed-anyway | killing the client does not leave NeedsRemediation (the deployment service finishes the update), so no guard action is needed; same as the earlier 24/24 on the test pair | n/a |

Repair time (cancel to package Ok with no action of ours): 12.6 s and 14.1 s, matching the earlier ~13 s on the self-signed pair. Retry-driven paths took 145 to 153 s because they wait for the restored feed plus the +2 min retry. `off200` and the baseline (guard removed) runs were not repeated; the earlier baselines (Reset-AppxPackage and platform re-register leave NeedsRemediation) stand for the test pair.

## Package smoke and single-package controls on the release-signed 0.1.0.0 (`signed-guest.json`, `packaged-window.png`)
No certificate import: installed on platform trust in 1.8 s, status Ok, window `SliceApp` 653 x 515 rendered (21581 colours, black fraction 0.013), WM_CLOSE exit in 20 s, no crash events; guard task registered 2.1 s after launch (event 751 + logon triggers, per-user, guard.json v2); healthy / task-deleted / uninstall controls PASS (uninstall cleanup 15.9 s, `rows.json` sha unchanged).

## Mac DMG (`dmg-check.txt`)
hdiutil verify VALID; spctl accepted (Notarized Developer ID, Adrian D'souza 6KLGD3LLKF); codesign valid; stapler validate worked for the DMG and the mounted SliceApp.app; app not launched. (Run 38538717695's DMG was not checked: it is not the old/new pair used here.)

## Notes
- The Sandbox had exited at 14:14 IST before the first job (cause unknown, nothing of ours running) and was restarted once with `client.py start`; it stayed minimised with no foreground samples.
- Not covered: a real user-driven cancel in the Settings UI, and the 240 ms offset (harness-timing limit, see the earlier receipt).
