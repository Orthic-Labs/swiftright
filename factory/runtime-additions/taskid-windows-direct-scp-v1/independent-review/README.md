# Independent direct-SCP review

Offline review covers exactly one focused test run for each `original`, `retained`, & `terminal` variant. No rerun, SSH, compiler, GUI, Pulse, source, or runtime edits were made.

Review script validates 135 planned source files, 137 v2 packet entries, exact per-variant 45-file bindings, source trees, unchanged assertions, 40 ms task body, 120 ms settle guard, runner preimage/plumbing, PowerShell path repair, `New-Item -Path`, reserved `$input` rename, raw stdout/stderr, tool/executable hashes, argv/cwd, CIM process joins, UTC process intervals, & one copied test runner per variant.

Results are bounded:

- `original`: exit `1`, raw `XCTAssertEqual` failure at `TaskIDTests.swift:91`, empty results.
- `retained`: exit `0`, raw `commit=true a`, results `["a"]`.
- `terminal`: exit `0`, raw `terminal=true`, `commit=true a`, results `["a"]`.

Packet pins: v2 manifest `48b82bd9a311f3e7289ff113feb117469143f11fdb7f0c971c3c3c61d936362e`, source plan `66ad3b9db201e956bde92f85a34b5c61585fc8036e285909ce5ba38325481c3c`, receipt `7ba2f71e210da0d33311f5be363dd07e703135acc89c230fba054a13b4bf6fca`, runner `82088f96f7f3ce80ba7bef91653693e39bcd0d0cbc0a38a6b35a0426ee6b8418`, Swift/SwiftC `1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a`.

Run `python3 -B review.py` from this folder. It writes `report.json` & `raw-pins.json`. Mutation controls alter source count, sleep, runner hash, retained exit, terminal marker, & retained result; each is rejected. Generic source-plan roots differ from fresh versioned actual roots, so review records regex/fresh-root acceptance. Historical v1 manifest retains one stale runner pin; v2 is exact.
