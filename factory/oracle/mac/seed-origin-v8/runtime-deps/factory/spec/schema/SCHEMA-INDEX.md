# Factory schema v0.1

Each root document uses JSON Schema draft 2020-12, `version: "0.1"`, a `kind` constant, canonical provenance & explicit hashes. Validator resolves relative references from this directory.

| Artifact | Schema | `kind` |
| --- | --- | --- |
| SDK inventory | `catalogue.schema.json` | `catalogue` |
| Curated implementation blocks | `block-registry.schema.json` | `block-registry` |
| Capability/channel obligations | `capability-obligations.schema.json` | `capability-obligations` |
| Reviewed witness specification | `recipe.schema.json` | `recipe` |
| Fixed generated/gate case | `case.schema.json` | `case` |
| One host-run capture & outputs | `capture.schema.json` | `capture` |
| Comparator result | `verdict.schema.json` | `verdict` |
| Executed-operation record | `receipt.schema.json` | `receipt` |
| Work queue item | `ticket.schema.json` | `ticket` |
| Maintainer waiver | `waiver.schema.json` | `waiver` |

`common.schema.json` supplies tagged numbers, tuple, hash references, provenance & envelope. Schema validation is structural: protocols impose cross-artifact rules, including unique IDs, hash verification, reviewed promotion & reciprocal dependency checks. Capture semantic comparison, host execution, hash calculation & promotion enforcement remain implementation work; schemas alone make no native-evidence or parity claim.
