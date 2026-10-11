# Independent review: seeded observations actual v1

The stage manifest, current report, raw pins, 100 Mac run inventories, 100 external-AX/capture joins, and five Windows single-run source/case/executable joins verify. Current instrumented raw bytes match current summaries for all 100 Mac runs.

**Disposition: hold proof-linked acceptance.** `proof-copy.json` and `lineage.json` agree with one another, but both reference different `instrumented.raw.json` and `capture.json` byte hashes from current captures in all 100 Mac runs. Current report pins match current raw trees; the lineage sidecar is stale relative to those captures. Preserve this distinction rather than rebuilding lineage or changing producer data here.

Semantic channels remain separated: scroll instrumented status is UNOBSERVED while external AX is OBSERVED; exact sequence claim is false. Custom external AX is reported held despite raw client status OBSERVED. Compiler OS origin is missing. `exitCode` and `ownedExited` are retained raw fields only and do not qualify OS termination or native shutdown. Parity, paint, focus, occlusion, timing qualification, and goldens remain held.
