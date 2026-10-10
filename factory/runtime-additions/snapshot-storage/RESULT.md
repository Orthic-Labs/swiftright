# Snapshot storage evidence

Base: `67b841fbbb5b8571a14390637bd875b62bf433ad`

Private exact-base copy: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/snapshot-storage/exact-67b841fb/runtime`

Patch uses integration paths `probes/sr0-s/fresh-runtime/...`; `patch --dry-run -p4` passed against private copy. Worker changed no primary source. Root integrated reviewed patch separately as `bbceb5a1`; its independent full suite also passed 171 tests.

Validation ran on internal disk:

- full suite: 171 tests, 0 failures; original 167 remain green, focused 4 pass
- stdout: [full-test.stdout](full-test.stdout), 452 lines/47,381 bytes
- focused cases: equal shape boxes, geometry/paint inequality, nil legacy metadata, retained snapshot immutability
- arm64 `ResolvedNode.stride`: base 648, patch 576

SHA-256 receipts:

| Item | SHA-256 |
| --- | --- |
| BASE | `5d56b4e3703b444b6796675cd1c3bfbcebf91cc94de85db5674619909683b49d` |
| 01-shape-storage.patch | `3327e4d22f777b85542f3944c15de841375ca6576432bf7ecd5330b588a3919b` |
| full-test.stdout | `28d4be3273e02ae374c3e4957ab3d2384043b592684c7470aa498b3e450baa5a` |
| patched Graph.swift | `c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f` |
| focused SnapshotStorageTests.swift | `653cf477745ae5936b6bb18584abef6c8c31e0a28e7dc0678a512050644851e2` |
| base Graph.swift | `82fa3fd168d252bed9b4f0532e8134741c5443223d0d55ae71e9989a0bf69b69` |
