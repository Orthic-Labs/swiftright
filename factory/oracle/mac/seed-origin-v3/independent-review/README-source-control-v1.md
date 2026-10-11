# Seed-origin v3 Mac source & positive-control review

Stage `d791a795f11dd0f1558177e96cb74f81bc2a435f7ce371f87a3f76ce5b38e503` has 42/42 entries present, with zero hash or size mismatches.

Archived positive control passes: one internal `xcrun swiftc` attempt, resolver PID/PGID 72358, compiler PID/PGID 72362, exit 0, source drift false, timeout false, tool drift false, receipt `8a10bd47…672af8c`, & 35,168-byte binary `515bbc6a…2d862b90`. Receipt joins logical swiftc argv, resolved swift-frontend hash, UTC/PID/PGID, cwd, raw stream hashes, equal source snapshots, & binary. Six v3 tests pass. No seed or GUI capture ran.

Review blocks seed admission. Nested `collector/capture_origin.py` uses `parents[4]`, resolving repository/factory instead of repository root; recorder, canonical case, recipe, font, & package paths then point under wrong prefixes. Archived `positive-control/run-control.py` also builds an absent `positive-control/factory/.../capture_origin.py` path, so recorded compiler lineage is not replayable from staged runner. `_safe_drain()` does not propagate first communicate timeout into `timedOut` when SIGTERM drain succeeds; such run could be marked successful after deadline breach.
