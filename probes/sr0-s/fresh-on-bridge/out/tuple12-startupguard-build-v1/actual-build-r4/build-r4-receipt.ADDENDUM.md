# build-r4-receipt.json: addendum (17 October 2026)

This addendum corrects `build-r4-receipt.json` in this directory. The receipt itself is not edited and remains the historical record of build r4 (`exitCode` 0, `sourceFilesVerified` 91, `sourceManifestSha256` `f45b9e0d…`, FreshOnBridge `87b8cb27…`, renderer `7578cd5d…`).

## Correction

- The receipt field `overlayCommit` `db08e1a11fbb61e3789c7c1687c936a33c06d523` names overlay r1 and is superseded. That commit carries `StartupGuard.swift` `fdd0f3c5…`, not the `05f2f684…` file that was built.
- The source actually built is transport manifest `f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca` (`transport-manifest-r4.json` in the parent directory). It records `overlayRevision` 2 and `overlayManifestSha256` `0d537b83d0bc761f1f78fee738b15199846fbb94125a4708aaf8ae9f0fcbb27a` (`qualification/tuple12-startupguard-overlay-r2.json`).
- The commit whose compiled closure equals that manifest is `a9556b77f50315afcae27fc8fc44c0cd274959e2` (base `0e201571e4320a3b6ccce14313fd2ad67e523904` plus overlay r2). This is the canonical tuple 12 stage commit.
- FreshOnBridge `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374` stays the tuple member. A non-identical rebuild at the stage commit is a reproducibility note, not a re-pin.

Decision record: `docs/sr1-decisions.md`, section "17 October: tuple 12 stage identity and renderer admission" (Sage adjudication; issues #17, #18, #20).
