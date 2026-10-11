# Mac origin admission v3

v3 repairs two frozen v2 faults while preserving v2 evidence unchanged. Live guard now requires exact mode-specific compiler argv templates: main `xcrun swiftc -parse-as-library -O -o <binary> Witness.swift CaptureHost.swift`; AX `xcrun swiftc -O -o <binary> AXClient.swift`; direct mode uses bound logical compiler path in same flag/source order. Extra flags or unbound sources anywhere are rejected. Malformed `CaptureHost.swift` source records & malformed `outputBinary` records produce issues without exceptions.

`test-receipt.json` records 3 passing focused tests, including unbound-before-output, malformed adapter, & malformed output controls. `compatibility-replay-v3.json` replays 5 archived Mac captures using exact archived bytes & recorded tool bytes only; `nativeOrCompilerRuns=0`, all 5 pass. No native/compiler execution occurred.

v2 report/source evidence remains under `mac-origin-admission-evidence-v2/`, including frozen reviewer report `independent-review/report-v2.json`.
