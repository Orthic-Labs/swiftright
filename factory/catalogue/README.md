# F1 SDK catalogue

Run from repository root with the factory environment:

```sh
factory/.venv/bin/python -m factory.catalogue extract
```

`extract` invokes `swift-symbolgraph-extract` for SwiftUI & SwiftUICore, emits extension-block graphs into ignored `factory/out/catalogue/raw/`, merges graph files by precise USR, audits SDK interfaces, and writes canonical evidence under `evidence/`. Use `--developer-dir`, `--sdk`, `--target`, `--out`, and `--evidence` to pin another local toolchain. `merge` rebuilds evidence from supplied graph and interface paths; `audit` reruns v1 name reconciliation; `audit-v2` reconciles by enclosing type/extension, kind, labels, and parameter types; `audit-v3` adds normalized generic `where` constraints & Swift-operator operand matching; `audit-v4` also normalizes all pinned SDK module qualifiers & uses exact return types as positive disambiguating evidence; `audit-v5` uses compiler-probed conditional branch selection from `evidence/tilde-sendable-compiler-probe.json`. Later audits accept optional `--comparison-graphs` for another target's graph set.


`evidence/sdk-signature-reference.json` is a scoped source-backed cross-reference for factory APIs used by SR1. It links declaration fragments & precise USRs to raw graph hashes, v5 interface rows/candidates, interface hashes, pinned SDK, compiler & target. `python -m factory.catalogue.signature_reference` regenerates it; `factory/.venv/bin/python -m unittest factory.catalogue.test_signature_reference` checks candidate USRs against the pinned catalogue, requested API groups & Layout geometry signatures. The reference preserves ambiguous/unmapped interface status from v5 and makes no completeness claim.

[Reviewed public-source candidate](public-ancestor-consumer/README.md) preserves original 108,272 symbol objects & 11 graph descriptors, then appends 3,304 qualified compiler USRs for 111,576 inventory symbols. [Pinned source proof](public-ancestor-spike/README.md) accounts for 17,846 declarations & 19,185 observed compiler records with zero holds; 56 producer changed-input controls & 34 independent faults pass. Consumer passes 25 tests & 83 independent faults, including typed sidecar counts & atomic pair rollback. [Registry review](../registry/public-source-binding-v2/independent-review/CLEARANCE.json) retains all 65 selectors across 10 blocks. Original graph catalogue stays immutable; candidate scope covers pinned SwiftUI/SwiftUICore source & observed compiler records.
