# W08 upstream handoff

W08 stays `FAIL` until `@rightkit/release` supplies one versioned repair path & fresh evidence. Installed `0.2.151` has no verified helper/remediation match; adopting it does not close W08.

Release owner must provide:

1. **Helper source & provenance** — helper/installer/feed implementation, exact upstream commit or package version, source archive hash, published package hash, supported Windows/runtime versions, & ownership of future fixes.
2. **Installer/feed integration** — final old/new MSIX pair, package identity/version, App Installer feed URL or local test host, manifest/update settings, signing receipt, certificate identity/timestamp, & explicit invocation from SliceApp update flow.
3. **Recovery contract** — documented command/API used after cancellation, expected exit codes, package-state transitions, idempotence, data/user-path preservation, relaunch behavior, & failure diagnostics. Manual Settings Repair or same-version redeploy alone is insufficient.
4. **Clean-machine evidence** — fresh VM/Sandbox run with update cancellation landing in `Modified, NeedsRemediation`; helper invocation must transition package to launchable state; capture before/after package state, old/new versions, app launch, persisted data, logs, & exact timestamps.
5. **Negative controls** — cancellation outside registration, helper on healthy package, wrong package identity, stale feed, corrupt package, & repeated helper invocation. Each must return expected nonzero/result state without data loss.
6. **Tuple12 binding** — receipts bind helper/source/package bytes to tuple12 source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`, renderer candidate `C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F`, & release metadata. Re-run package qualification after any changed byte.

Acceptance requires release owner review, exact receipt files & hashes, reproducible helper invocation, cancellation-state repair, relaunch, data-integrity proof, & package signature proof. Until then freeze stays held, approved 20-per-side comparison remains required, & Narrator listening remains later human follow-up.
