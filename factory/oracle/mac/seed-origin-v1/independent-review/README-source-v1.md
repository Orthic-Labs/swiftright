# Seed-origin v1 Mac source review

Offline review pinned stage `e09db3ec98db37c921a0022dc946ae6ceefd7481711accb2258ed5a2b5998324`: 31/31 entries present, with zero hash or size mismatches. Exact seed `14577611000270672472` covers five cases: stack-overlay, padding-frame, scroll-view, custom-layout, & preference-key.

Receipt design is source-clear for resolved `swiftc` argv semantics, resolver/compiler PID plus UTC bounds, raw stdout/stderr hashes, compiler/xcrun hashes, pre/post Witness plus adapted CaptureHost snapshots, output binary hash, internal scratch restriction, no-prompt AX/screen preflights, symlink-resolved font validation, & own-process-group handling in generic `run()` and fresh AX capture.

Review blocks execution. `capture_origin.py:185-192` sends compiler process group SIGTERM after 120 seconds, then waits five seconds with no SIGKILL fallback or final drain. A compiler descendant holding pipes can leave owned work unfinished, raise uncaught `TimeoutExpired`, & prevent receipt/status emission. Resolver `rp.communicate()` at line 174 has no timeout or cleanup, giving second boundedness block.

`test_source.py` contains three static controls; reviewer did not execute tests, compiler, capture, GUI, or SSH. Root can proceed only after source repair, fresh source pins, & bounded internal-cache controls.
