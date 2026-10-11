# Seed-origin v4 Mac source & control review

Stage `f81a3746b850bc773e3cd6aa249b170ea9d48002b3516ee0956115233d743840` has 51/51 entries present, with zero hash or size mismatches.

Positive compiler control passes: one internal run, resolver PID `56290`, compiler PID/PGID `56298`, exit `0`, source/tool drift false, timeout false, receipt `61c86f27…f8958a92`, & 35,168-byte binary `515bbc6a…d862b90`. Logical `swiftc` argv, resolved `swift-frontend` hash, source pre/post, UTC/PID/PGID, cwd, raw streams, xcrun hash, & binary join. Timeout control passes: PID/PGID `62663`, initial timeout true, TERM true, exit `-15`, no retry, receipt `7ffee18b…c40e184`. Six v4 tests pass. No seed or GUI capture ran.

Seed admission remains blocked because stage has no `AXClient.swift` or `CaptureHost.swift`; `fresh_ax_preflight()` and `capture()` read those sibling files. Positive archive map also omits source fixture files, so receipt source hashes depend on internal paths without archive-level source join. Add and pin capture sources plus archive joins before capture.
