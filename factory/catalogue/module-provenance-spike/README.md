# F1 module provenance spike

Version 2 reconstructs 33 qualified-module holds from immutable836 link evidence `sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.

`exact_validator.py` independently reads frozen row signatures, pinned SDK sources, raw SourceKit member/origin records & exact index requests. It reconstructs complete extension/nominal paths, conditional branches, declaration access/kind/name/line, contiguous annotations belonging to each of six origins, & freshly executed strict `swift-demangle --expand` trees. Every input byte & tool identity is pinned. Bridge & v9 artifacts are lineage only; no derived owner receipt supplies identity authority.

`investigate_module_provenance.py` validates all 33 baselines before each of 346 byte-distinct faults against production validator. Faults edit raw member/origin records, source declarations, module/full-owner scopes, annotations/conditions, reexport, actual tree text & request identity. Duplicate records & trees fail closed. Receipt replay reconstructs rows & reruns every fault rather than trusting recorded booleans.

`module-provenance-evidence-v1-lineage.json` preserves prior receipt for history; its self-comparison controls are superseded. Current result remains review-only, retains 33 holds & promotes zero catalogue rows.

```sh
python3 factory/catalogue/module-provenance-spike/investigate_module_provenance.py
python3 factory/catalogue/module-provenance-spike/test_module_provenance.py
```
