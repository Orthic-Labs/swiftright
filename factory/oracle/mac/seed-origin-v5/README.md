# Seed compiler-origin complete dependency closure v5

V5 preserves v4 through `v4-lineage.json`. It adds exact sibling `AXClient.swift` & `CaptureHost.swift`, explicit collector runtime dependency copies, 12 schema files, archived compiler source joins, & receipt validation against archived bytes. `runtime-deps/dependency-hashes.json` pins 22 imported source files; dependency verifier passes.

One fresh positive compiler control ran once from `seed-origin-v5-control-20261011`: resolver PID `25684`, compiler PID `25705`, exit `0`, source drift false, tool drift false, timeout false. Receipt SHA-256 `b58897d90fa4aca158c8d428f4ff6971737633aac2e4d88510077c49e6dfb53d`; emitted binary is 35,168 bytes with SHA-256 `515bbc6a5cbd1d7a7bb434b870a8f1a2a44849ab6dcbc39f69d060b32d862b90`. Source receipt paths, argv paths, source-input copies, & archived source bytes all join exactly.

One owned timeout fault control ran once from `seed-origin-v5-timeout-20261011`: PID/PGID `29367`, initial timeout retained, TERM sent, exit `-15`, no retry. Timeout receipt SHA-256 `0a0c3156f93747b07ac7039613a3165642201db4b0624f42551b3c9a1dc67837`. Positive, timeout, & dependency verifiers pass; v5 tests returned `7/7`.

V5 source review is required before any seed capture. No seed, GUI, Accessibility, or external capture ran.
