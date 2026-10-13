# W08 upstream handoff

W08 stays `FAIL` until `@rightkit/release` supplies one versioned repair path & fresh evidence. Installed `0.2.151` has no verified helper/remediation match; adopting it does not close W08.

Release owner must provide:

1. **Helper source & provenance** — helper/installer/feed implementation, exact upstream commit or package version, source archive hash, published package hash, supported Windows/runtime versions, & ownership of future fixes.
2. **Installer/feed integration** — final old/new MSIX pair, package identity/version, App Installer feed URL or local test host, manifest/update settings, signing receipt, certificate identity/timestamp, & explicit invocation from SliceApp update flow.
3. **Recovery contract** — documented command/API used after cancellation, expected exit codes, package-state transitions, idempotence, data/user-path preservation, relaunch behavior, & failure diagnostics. Manual Settings Repair or same-version redeploy alone is insufficient.
4. **Clean-machine evidence** — fresh VM/Sandbox run with update cancellation landing in `Modified, NeedsRemediation`; helper invocation must transition package to launchable state; capture before/after package state, old/new versions, app launch, persisted data, logs, & exact timestamps.
5. **Negative controls** — cancellation outside registration, helper on healthy package, wrong package identity, stale feed, corrupt package, & repeated helper invocation. Each must return expected nonzero/result state without data loss.
6. **Tuple12 binding** — receipts bind helper/source/package bytes to tuple12 source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`, renderer candidate `7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2`, & release metadata. Re-run package qualification after any changed byte.

Acceptance requires release owner review, exact receipt files & hashes, reproducible helper invocation, cancellation-state repair, relaunch, data-integrity proof, & package signature proof. Until then freeze stays held, approved 20-per-side comparison remains required, & Narrator listening remains later human follow-up.

## Tier 2 repair guard: Sandbox acceptance (2026-10-13)

Commits `71aa269e0` (guard), `8a92c9bd0` + `bff7c2a85` (fixes below). Guard = `packages/SwiftRightBridge/guard/repair-guard.ps1`, installed by `Bridge.run` on each packaged launch as per-user task `<PFN>-Repair` (event 751 + logon). Runs: long-lived minimised Windows Sandbox worker (`factory/tools/sandbox/client.py w08`, software rendering), test packages `.work/w08t2/pkgs-t4` (old sha256 `731F6B9A...956F`, new `85D2CDDD...3382`; sealed Tier 1 pair with a rebuilt `SliceApp.exe`, self-signed `CN=SwiftRight W08 Test`, tuple 12 renderer `954977...`). Not release-signed packages; the guard code path is the product's.

Defects found and fixed (both were the reason no recovery could ever be observed):
1. Packaged launch crashed (`0xc0000409`, ucrtbase, WER event 1000, FAST_FAIL) inside `RepairGuard.installIfNeeded`: Foundation `Process` with `FileHandle.nullDevice` stdio fast-fails in a packaged Windows launch. Proof: same package with `SWIFTRIGHT_REPAIR_GUARD=0` runs; unpackaged exe runs; guard on crashes right after writing `repair-guard.ps1`. Fix: `CreateProcessW` + `CREATE_NO_WINDOW`. Not a renderer problem (no change to render/ or the tuple 12 pins).
2. Guard repair mode never ran: `New-Object Threading.Mutex($false, ...)` bound the 4-argument form and threw before the first log line (the task action runs under `conhost --headless`, which hides the failure and exits 0). Fix: `[Threading.Mutex]::new`; also decode a `byte[]` feed body (`application/appinstaller`), and log any unhandled error (exit 4).
3. Harness: `Start-Feed` restart after the feed-down kill failed (stale http.sys sslcert bindings); now deletes them first.

Results (induced = `Modified, NeedsRemediation` with event 751; no action of ours, launch via `shell:AppsFolder`, package Ok, `rows.json` sha equal to the written marker sha, marker row shown in the UI):

| Run | Offset (ms after staging; cancel at) | Induced | Recovered | Seconds cancel to Ok | Launch OK | Data hash OK |
|---|---|---|---|---|---|---|
| r360-a | 360 (443) | yes | yes, 0.1.1.0 Ok | 12.5 | yes | yes |
| r360-b | 360 (430, 2nd attempt) | yes | yes | 12.7 | yes | yes |
| r400-a | 350 (407, 4th attempt) | yes | yes | 13 | yes | yes |
| r400-b | 400 (513) | yes | yes | 12.5 | yes | yes |
| feed-down fd-b | 350 (424) | yes | stays NeedsRemediation with feed down; repair.log `FAILED ... feed unreachable ... msix unreachable`; Ok 11.9 s after feed restored | n/a | yes | yes |
| feed-down fd-c | 350 (416, 8th attempt) | yes | same: explicit failure logged, Ok 13.1 s after feed restored | n/a | yes | yes |
| uninstall un-a / un-b | none | n/a | task and `%LOCALAPPDATA%\SliceApp\repair` removed 15.3 s after Remove-AppxPackage (task started as the logon stand-in); `rows.json` and parent folder kept | n/a | n/a | yes |

Not met as asked: offset 240 ms. In this Sandbox the cancel at 240 (actual 297-328 ms after the call) always lands in the Staged state handler and Windows rolls back cleanly (`old-ok`, 16/16 attempts over two runs; 300/320: 8/8 `old-ok`); NeedsRemediation needs the cancel at about 350-440 ms, where it is probabilistic (`completed-anyway` when later). The offset is VM timing, not guard behaviour, so 360 and 400 stand in for 240; the 240 result is a harness induction failure, not a guard failure.

Evidence: `qualification/clean-machine/windows/w08-tier2-sandbox-20261013/<run>/{log.txt,result.json,post.jpg}` (`sweep1` = first induction plus the pre-fix run where the task ran and logged nothing; `rep240-a`, `r240-a`, `r300-a` = induction failures). Live copies: `D:\Claude\swiftright\.sandbox\results\<job>\`. Crash evidence: Sandbox Application log event 1000, WER `ReportArchive`.

This is Sandbox evidence for the in-runtime guard, not independent review and not W08 closure; the release owner decision on RightKit ownership stands.
