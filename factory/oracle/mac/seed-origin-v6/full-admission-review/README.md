# V5 full admission review

Read-only review of frozen v5 stage `sha256:a7dc3b2ba69042530f73ec4b892d29e517737de44a56f736f16a6bcab58d765a` (80 entries, 282793 bytes). Dependency closure, positive compiler source/binary receipt joins, timeout control, & 7 offline tests pass. Decision: `HOLD_FRESH_AX_COMPILER_RECEIPT`.

Five gate-seeded manifests bind canonical case hashes, live recipe canonical hashes, generated Swift source hashes, & witness source hashes. No font resource is declared for these five cases. `AXClient.swift` & `CaptureHost.swift` are exact sibling sources. Preflights call `AXIsProcessTrusted()` & `CGPreflightScreenCaptureAccess()` only; denied permissions emit `HELD` with `permissionRequests:false`. No request API appears in either Swift source.

Run command is recorded in `report.json`. It sets `SWIFTRIGHT_REPO_ROOT=/Volumes/D/claude/swiftright`, uses `factory/.venv/bin/python`, case root `seed-origin-v5/inputs`, 20 runs per manifest, internal scratch `/Users/adrdsouza/Library/Caches/SwiftRightFactory/...`, & evidence output under `factory/native/macos/evidence`.

After capture, accept each case only when compiler receipt, Witness/adapter source, binary, run raw/PNG, normalized capture, external AX owner, & compositor hashes satisfy joins listed in `report.json`. Keep unavailable channels `HELD`; retain `candidateOnly:true` & `acceptance:not-promoted`.

Fresh AX preflight currently compiles `AXClient.swift` through `xcrun swiftc` but keeps only stdout/stderr. Strict admission needs same OS compiler receipt & source/output joins for this helper, or helper build must be skipped when external AX is held.
