Last updated: 2026-10-17 (full RightKit port, Adrian's order)

# SwiftRight — RightKit port status

Full port ordered by Adrian on 17 October 2026 ("No further development till I have a commit with full port and removal of old code"). Scope he chose: product and live tooling sites with a RightKit owner, old code deleted, every gap filed, frozen run copies left alone. Site map: 40 sites (9 product, 31 tooling). Gaps are on bogusyogi/rightkit; triage by the RK3 Mac lead.

| RightKit component | State |
|---|---|
| @rightkit/release | adopted (root pin 0.2.162); release scripts now use `detachWithRetrySync`, `sha256File`, `readZipEntry`; the MSIX repair guard is generated from `msixRepairGuard()` (packages/SwiftRightBridge/tools/gen-repair-guard.mjs) |
| @rightkit/ci (right-git) | managed ci.yml and release-candidate.yml re-synced to template 1.8.0; render-windows.yml and probe-f0-text.yml stay hand-written (gap rightkit#465, post-port) |
| rightkit-logs | renderer SWR_FRAME_LOG trace file through `RotatingTextWriter` (0.3.0, Windows only); the grep-matched `[swiftright-render]` stderr lines stay `eprintln!` until an unformatted stderr line writer exists (rightkit#505, delta on #453) |
| RightKit build broker | adopted for Rust renderer builds |
| rightkit-qa (through right-release qa) | adopted for package QA receipts |
| RightKit ownership scan / trust floor | adopted as release gate |
| RightKitSwift | not used yet. Windows Swift product code (SwiftRightServices engine client, wire, config, fake engine; SliceApp Windows logging; RepairGuard installer) waits on a Windows-buildable subset (rightkit#450). SliceApp's macOS RowStore (RightKitFS 0.8.0) and the Mac AX probes (RightKitAccessibility, #441) are held because bogusyogi/rightkit is private and SwiftRight is public (rightkit#508; a public mirror is Adrian's call) |
| RightKit QA CLIs (rightkit-qa, -qa-interactive, -record-helper, right-ctl) | not installed on the Mac or the Dell; the live tooling ports to them (interactive tasks, capture, desktop lock, tree kill, process supervision, UIA driving) wait on rightkit#430 |
| Post-port gaps (test tooling and CI) | rightkit#431-436, #437, #439, #440 (in port), #442, #443, #445, #465; closed as wrong asks: #438, #444 |

SR0 state: OPEN. Tuple 12 source closure is `4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2`; managed recovery `rr-1791721085329-353f80ea918740ef` succeeded exit 0 with one granted Cargo job at 2026-10-11 12:33:41Z, process reaped. Receipt: `probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/status-jobs1-r3.stdout.bin`. Exact DLL bytes/path & complete closure remain unadmitted; `Cargo.lock` changed `e1d7816a…`→`7ae3c084…`. Tuple 12 is not staged or qualified. Tuple 11 remains last qualified baseline.

Blocked on RightKit: W08 repair-helper proof. Installed release 0.2.151 has no verified repair/remediation helper match. W08 must be fixed upstream; adoption of release 0.2.151 is not W08 proof. Freeze remains held. User accepted 20 Mac & 20 Windows runs per config; Narrator speech listening remains later.
