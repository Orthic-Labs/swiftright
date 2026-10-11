# Public ancestor catalogue

## Versioned candidate

`catalogue-public-source-v1.json` is schema-valid strict-v0.1 catalogue built from original base catalogue plus exact compiler-USR supplement. It has 111,576 symbols: original 108,272 symbol objects remain byte-semantically identical as prefix, followed by 3,304 sorted unique USRs absent from original 11-graph USR set. Base graph descriptors & symbol metadata remain unchanged. Candidate ID, provenance, & `sourceHash` describe augmented artifact; base `sourceHash` is retained only as base provenance and does not claim candidate identity.

`catalogue-public-source-v1.manifest.json` binds exact candidate bytes/canonical hash, immutable base hashes, accepted proof & guard, immutable 836 source-link, all proof-input refs, source/compiler counts, & `createdAt`. Child coverage distinguishes 2,008 USR groups from 2,013 raw records. Writes validate strict integer shapes & compare every coverage value against accepted resolution. Candidate & manifest are written as an atomic pair with rollback on replacement failure.

Candidate byte SHA-256: `fd453b6345f83b49931c7194c2e1127538e2de4ceb0de4c25f715ac6d85ac4f2`. Sidecar SHA-256: `322543df1789a202301ac159089ec33b20487fe268db90d90d3a2948888fbbb4`. Shared fixed timestamp: `2026-10-11T01:12:24.000000Z`.

## Accepted proof & review

Consumer pins exact production guard SHA `0ad49986e9f48fc66bc0f02683e3924f829babbb1e0aaa26c2354c68315e8889`, gzip proof SHA `7fbcab45c711446d93b4e0fb9d9161379ada01a414934b6f47ff95db0d4e6baa`, reconstructed raw SHA `8af5faea52769717aadadd3b98ef74237a05304f3d6eff025fdc9572b7fe07f1`, & raw size 138,987,898 bytes. `build_final_candidate` uses production `load_artifact` with stored & raw pins; proof loader independently reconstructs whole source/record/child resolution before returning. If any original graph is absent, pinned archive reader reconstructs all 11 files losslessly, rechecks each descriptor and whole-file hash, then verifies immutable 836 graph closure. A changed present original fails closed.

Proof accounting covers captured SwiftUI & SwiftUICore interfaces only. It reconciles 17,846 source declaration starts, 19,185 compiler records, 11,942 primary compiler USRs, & compiler child evidence; held source/compiler-child rows are zero. Five public-typed getters capped by nonpublic owners remain excluded from candidate. This is not certification of every SDK module, generated/compiler-only API family, future SDK, or runtime/native qualification.

Independent consumer clearance: [review report](/Volumes/D/claude/swiftright/factory/catalogue/public-ancestor-consumer/independent-review/final-candidate-v1/final-clearance.json), SHA `4e38d83cd837173d5f699ee63679064920ab7e811724bed7c6f60c330e3501c7`; [review stage manifest](/Volumes/D/claude/swiftright/factory/catalogue/public-ancestor-consumer/independent-review/final-candidate-v1/root-stage-manifest.json), SHA `a97985ce…`. Review verified forced archive replay, all 108,272 base rows & 11 graph descriptors, 3,304 additions, five exclusions, 2,008 groups/2,013 records, 69 recursive sidecar faults, 10 child-count faults, 4 gzip-pin faults, & actual pair-rollback behavior. Consumer suite passed 25 tests; [result receipt](/Volumes/D/claude/swiftright/factory/catalogue/public-ancestor-consumer/test-receipts/consumer-suite-final-v1.json), SHA `264bd9a928766690870f6b17cb9ad682bb91755b98ce5869c590105f0389fc31`.

Source accounting's [final proof input-stage manifest](/Volumes/D/claude/swiftright/factory/catalogue/public-ancestor-spike/final-input-stage-manifest-v2.json) has SHA `75efb40e74733ba876757d7deb367d2745fddcc6d9edbcc00d50c421ce1ee024`. Its producer suite passed 56 fault controls; receipt SHA `688358ac02748fc785e3997729d2978b44861b562b91a98a0e6f7e440256f944`. F2's exact candidate comparator v3 is independently clear for the frozen 65 selectors across 10 blocks; comparator source SHA `7589dc6ff0754b66a380a0e59565fc05535d04f9f258ef58dab86035ad125659`, owner-stage SHA `1f282223050a32fabeddb2c5c80205616937ac02d86c042180406bdbf18b8b9a`, clearance SHA `4e293ffa85fed5ac118ee504a27ad6da69fb93a359b4a26547847475d9cb4b4c`.

## Verification

```sh
PYTHONPATH=. factory/.venv/bin/python factory/catalogue/public-ancestor-consumer/test_consumer.py
```

Proof producer replay is separate:

```sh
PYTHONPATH=. factory/.venv/bin/python factory/catalogue/public-ancestor-spike/test_public_ancestor.py
```

Both suites bind source/artifact hashes from their reviewed evidence; do not replace exact pins with hashes computed from mutable inputs.

## Historical source census

The separate raw census v1 is historical & unrepeatable because its original parser bytes are unavailable. Its preserved source-preimage is under `lineage-pre-proof-pins-v1/`; corrected parser/source accounting lives under `factory/catalogue/public-ancestor-spike/full-source-census-v2/` & is independently bound by final proof. Earlier consumer source/test/candidate preimages remain in versioned `lineage-*` folders. No raw SDK source or compiler binary is bundled here.
