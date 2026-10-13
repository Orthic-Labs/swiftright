# F10 Rectangle reader input v3

Source-only adapter for measured `actual-count20-r4/export-manifest.json` plus explicit `artifact-bytes-r1/export-manifest.json`. It requires producer count equal to current Windows row count (1023 in measured export), exact native-01..native-20 proof roles, global source/runtime/compile/parent roles, & three measured artifact roles (`compiler`, `exe`, `renderer`) joined by path, bytes, & SHA.

It emits merged manifest metadata only; it does not copy, discover, alias, qualify, grant parity, or claim golden status. `qualified=false`, `nativeParityGranted=false`, & `nativeActions=0` remain fixed until trusted production reader/admission consumes this map.

Reader handoff requires root-authored input manifest with exact `macReport`, `windowsCaptures`, `macRoots`, `macPathMap`, & 20 `windowsArchives` rows. Run trusted reader only after r4 status is ready, then run paired diagnostic; keep parity/golden/freeze held. Seeded rejection cases must each use fresh mutated copies: remove one archive row, alter artifact bytes/SHA, wrong tuple/case, duplicate run/capture ID, or clear parent certificate. Each must return blocked/exit 2; never mutate measured exports.

Root command shape:

```text
python prepare_f10_adapter_input.py --export-manifest <actual-count20-r4/export-manifest.json> --artifact-export-manifest <artifact-bytes-r1/export-manifest.json> --expected-tuple <measured-tuple.id> --expected-case <measured-case.id> --output <fresh-input-map.json>
```

```text
python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/trusted-reader-report.py --input <root-authored-f10-input-manifest.json> --output <fresh-trusted-reader-report.json>
python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/run-paired-comparison-r3.py --input <same-root-authored-f10-input-manifest.json> --output <fresh-f10-diagnostic.json>
```
