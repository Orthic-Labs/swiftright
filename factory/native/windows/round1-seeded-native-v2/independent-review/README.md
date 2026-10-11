# Seeded-native-v2 source review

Source stage `cbdbf5e5957d7a68c6a8c0f2ecc0ec87f4ef991dc86a3569d65145febacccc93` contains 186 pinned files; local verification found 0 missing & 0 hash mismatches.

Proof join `proof/source-join.json` is pinned to `9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3`; proof contract is `2a2f4f64da212cb187ff893dcade8c774ef292d7618dc511c455473bb00ec0b1`. Five exact cases have 20 runs each: 80 `OBSERVED`, 20 scroll-view `UNOBSERVED`; compiler origin, Windows compile, native parity, & GUI qualification remain held.

Source permits root to run pure PS5 controls. Controls cover AST parsing, changed proof bytes, wrong source/seed/case/plan/witness/host/binary, duplicate/missing/string runs, bool scope fields, raw/capture status, receipt/executable/stream/exit faults, duplicate namespace rows, ownership, close ordering, stream sealing, & lock release. `run-repeat.ps1` validates fresh five-host Windows receipt/executable lineage before lock acquisition; owned-close, stream, cleanup, & namespace hashes are recorded in report.

Root may proceed with bounded controls. Fresh five-host Windows receipt/executable proof remains required before GUI/native dispatch.
