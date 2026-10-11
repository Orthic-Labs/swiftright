# Mac origin admission v4

v4 repairs two nested JSON faults identified by frozen v3 review while preserving v3 evidence unchanged. `receipt.invocationMode` now requires string type before membership checks. `summary.freshAXClient` must be an object whenever present, including valid auxiliary AX receipts. Public `mac_origin_admission_issues(capture, reader)` converts malformed nested JSON exceptions into rejection issues.

`test-receipt.json` records 3 passing focused tests with malformed invocation mode, null/list AX descriptors, malformed adapter/output, & exact argv controls. `compatibility-replay-v4.json` replays 5 archived Mac captures using exact archived bytes & recorded tool bytes only; `nativeOrCompilerRuns=0`, all 5 pass. No native/compiler execution occurred.

v3 evidence, reviewer report, source snapshot, & actual replay remain frozen under `mac-origin-admission-evidence-v3/`.
