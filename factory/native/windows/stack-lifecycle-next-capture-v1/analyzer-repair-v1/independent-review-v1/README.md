# Analyzer repair independent review

Offline review of analyzer-repair-v1 stage `af8476f02095cfe768e72b6c298e33a0f1089924c02280b7c0cdc600bdfc3948` (73 refs). Every stage ref matches path, bytes & hash. Repaired analyzer has fixed source plan `9e385e4e…acef1`, actual compile receipt `99a0332b…dcae8`, original owned-process join, exact compiled exe join, typed two-stream terminal/closure/sealed checks, & recomputed stdout/stderr hashes joined to outcome/timing. Existing nine offline controls pass: baseline accepted; eight intended faults rejected. Frozen capture stage remains `4cb0602f…f7eb4` with 24 refs.

Raw Count1 capture guard admission is clear independently of analyzer: runner/preflight/coordinator source controls, actual Windows AST/source controls & actual Launch preflight are separate gates; all are archived as passed by root. Final native run still depends on root-held runtime lock & raw exit/stream receipts.
