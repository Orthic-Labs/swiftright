# Mac origin admission v2

v1 blocked source snapshot is retained under `independent-review/historical-v1/`. Live v2 uses schema-valid `capture.meta.conditions.macOrigin`; top-level `macOrigin` is rejected.

Required origin refs: `summary`, canonical `case`, `source` (`Witness.swift`), `adapter` (`CaptureHost.swift`), `binary`, & `compilerReceipt`. Main receipt requires exact two-source inventory, compiled adapter hash joins, resolver identity/chronology, exact mode/argv/output/source shape, tool pre/post bytes, owned process groups, UTC timing, natural exit, cleanup, raw streams, & authoritative root `receipt.sourceDrift=false`. `freshAXClient.externalAX=AVAILABLE` requires exact auxiliary receipt/source/binary refs & summary joins; held AX may omit auxiliary refs.

`compatibility-replay-v2.json` replays five archived actual Mac receipts through live guard with exact archive hashes & recorded current tool bytes only; no compiler/native execution. Focused test receipt records 3 passing tests with isolated fault controls.
