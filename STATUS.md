Last updated: 2026-10-11 (tuple12 takeover)

# SwiftRight — RightKit port status

| RightKit component | State |
|---|---|
| @rightkit/release | adopted 0.2.151 for current source & qualification work; prior qualified Windows packages used 0.2.146 |
| RightKit build broker (rightkit cargo / rightkit remote windows cargo) | adopted for Rust renderer builds; current broker audit READY, owners empty, inFlight empty |
| rightkit-qa (through right-release qa) | adopted for package QA receipts |
| RightKit ownership scan / trust floor | adopted as release gate |
| RightKitSwift | not used: SwiftRight has no dependency on it |
| Other RightKit crates & UI packages | local or not applicable: SwiftRight is SwiftUI-semantics runtime & renderer |

SR0 state: OPEN. Tuple 12 source closure is `4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2`; managed recovery `rr-1791721085329-353f80ea918740ef` succeeded exit 0 with one granted Cargo job at 2026-10-11 12:33:41Z, process reaped. Receipt: `probes/sr0-s/fresh-on-bridge/out/tuple12-renderer-recovery-v1/status-jobs1-r3.stdout.bin`. Exact DLL bytes/path & complete closure remain unadmitted; `Cargo.lock` changed `e1d7816a…`→`7ae3c084…`. Tuple 12 is not staged or qualified. Tuple 11 remains last qualified baseline.

Blocked on RightKit: W08 repair-helper proof. Installed release 0.2.151 has no verified repair/remediation helper match. W08 must be fixed upstream; adoption of release 0.2.151 is not W08 proof. Freeze remains held. User accepted 20 Mac & 20 Windows runs per config; Narrator speech listening remains later.
