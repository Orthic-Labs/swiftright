# W08 upstream diagnosis & acceptance gate

W08 failure is bounded to cancellation during MSIX registration. Existing receipts show `IAsyncInfo.Cancel()` at staging +200–360 ms reaches `RegistrationChanged`, returns `0x80073CF8` / event 751, leaves old package `Modified, NeedsRemediation`, blocks launch, & preserves external data. `KillClient` is not an interruption: deployment service finishes after client death. Evidence: `examples/SliceApp/RESULT-R5-10.md`, `examples/SliceApp/RESULT-R5-W08-recovery-08.md`, `docs/sr0-findings.md` §3.11 & L2.

Measured recovery proves install-source redeploy is effective: same-version `Add-AppxPackage -Path` & `-AppInstallerFile`, plus Settings Repair, restored `Ok`, launch & data. `RegisterByPackageFullName`, `RegisterByFamilyName`, `Reset-AppxPackage`, & relaunch alone did not. Repair requires retained MSIX/feed source. Installed `@rightkit/release` 0.2.151 has no verified repair-helper/remediation match; adoption is not proof.

Required RightKit owner handoff:

1. Provide helper/installer/feed source path that is available after interruption, or provide rollback-before-registration behavior that leaves old package launchable.
2. On `Modified, NeedsRemediation`, run same-version redeploy, verify package state `Ok`, relaunch, version, & data marker hash.
3. Run cancellation delays spanning registration (200, 240, 280, 320, 360 ms) in fresh guests, with 8/8 induction attempts or recorded non-induction. Keep package pair/source hashes & deployment events.
4. Exercise idempotent second recovery, missing-source failure, `KillClient`, platform registration, `Reset-AppxPackage`, & relaunch-only controls. Controls must remain rejected as recovery.
5. Bind receipts to RightKit release/helper hash, package/feed/MSIX hashes, source availability, final status, process path/version, & data hash. W08 closes only after owner review accepts every receipt.

The W08 repair guard is the one admitted exception to "no local workaround": its canonical home is RightKit (`packages/release/msix-repair-guard.ps1`, exported by `msix-repair-guard.mjs` with its sha256), and SwiftRightBridge consumes a byte copy pinned by `packages/SwiftRightBridge/guard/rightkit-pin.json` (decision 6 in `docs/sr1-decisions.md`, under Adrian's 2026-10-13 grant). No other local render, bridge, fixture, or package workaround is admitted. Freeze remains held; Narrator listening remains later; new package signing remains short-lived Azure reissue under root-managed signing lane.
