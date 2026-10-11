# Seed compiler-origin corrected control v4

V4 preserves v3 through `v3-lineage.json` & repairs three defects: collector root detection uses validated `SWIFTRIGHT_REPO_ROOT` or a known `factory/core/artifacts.py` marker; archived runner resolves its collector from its detected repository; `_safe_drain` records first timeout even when TERM drains successfully. V2 failure & v3 positive control remain immutable.

One fresh internal positive control ran once from `seed-origin-v4-control-20261011`: xcrun resolver PID `56290`, compiler PID `56298`, exit `0`, source drift false, tool drift false, timeout false. Receipt SHA-256 `61c86f270a93d580cf73eaece5c581ce14b699b01f4d406dd3ab3010f8958a92`; emitted binary is 35,168 bytes with SHA-256 `515bbc6a5cbd1d7a7bb434b870a8f1a2a44849ab6dcbc39f69d060b32d862b90`. Real `swift-frontend` is 173,118,384 bytes with SHA-256 `84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7`.

One owned timeout fault control ran once from `seed-origin-v4-timeout-20261011`: PID/PGID `62663`, initial timeout recorded true, TERM sent, exit `-15`, no retry. Timeout receipt SHA-256 `7ffee18ebd198aba7f3d4ac4b7675041d9e38bb513f601a8a451434a3c40e184`. V4 tests returned `6/6`; positive & timeout verifiers returned PASS.

V4 source review is required before any seed capture. No seed, GUI, Accessibility, or external capture ran.
