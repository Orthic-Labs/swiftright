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

SR0 state: OPEN. Tuple 12 renderer candidate is `C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F`, source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`; Dell stage root was absent after parser failure, so tuple 12 is not staged or qualified. Tuple 11 remains last qualified baseline.

Blocked on RightKit: W08 repair-helper proof. Installed release 0.2.151 has no verified repair/remediation helper match. W08 must be fixed upstream; adoption of release 0.2.151 is not W08 proof. Freeze remains held. User accepted 20 Mac & 20 Windows runs per config; Narrator speech listening remains later.
