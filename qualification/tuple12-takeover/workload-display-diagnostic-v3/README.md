# Tuple12 display diagnostic v3

Source-only successor to v2. It admits sampler launch only when wrapper `ProcessIdToSessionId` equals `WTSGetActiveConsoleSessionId`, checking before workload start & again before sampler start. Mismatch emits `session-mismatch` receipt & preserves lock. v6 owned-job helper remains responsible for suspended creation, assignment before resume, bounded drains, caps, active=0, terminal proof, & handle retention.

No UI activation, permission change, session creation, or unrelated process control. Root must refresh hashes, run controls, then perform any Windows run.
