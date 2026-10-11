# Seed compiler-origin positive control v3

This namespace preserves v2 collector bytes & v2 failed control. v2 failure remains at `factory/oracle/mac/seed-origin-v2/control/failure-20261011` with exit 1, missing `@main` entry point, no binary, & no retry.

V3 adds one corrected two-file Swift fixture: `Witness.swift` plus `CaptureHost.swift` with `@main`. One fresh internal `/Users/adrdsouza/Library/Caches/SwiftRightFactory/seed-origin-v3-control-20261011` xcrun `swiftc` process ran once. It exited 0, source drift false, timeout false, tool drift false, & emitted 35,168-byte binary. Resolver exited 0. Compiler PID was 72362; resolver PID was 72358. Logical compiler was `/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc`; resolved real compiler was `swift-frontend`, SHA-256 `84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7` (173,118,384 bytes). `/usr/bin/xcrun` SHA-256 is `bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9`.

Receipt SHA-256 is `8a10bd47c97dc0ed0f8c49a3b6562c35f3ab8fa4875ebdc035bd6e095672af8c`. Binary SHA-256 is `515bbc6a5cbd1d7a7bb434b870a8f1a2a44849ab6dcbc39f69d060b32d862b90`. `verify_positive_control.py` returned PASS; v3 tests returned 6/6. Symlink logical-path, source-drift, timeout, and compiler receipt controls are exercised offline.

This is compiler-origin control evidence only. No seed or GUI capture ran. Source review remains required before any seed capture.
