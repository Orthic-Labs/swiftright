# Structural F1 context bridge

`context-bridge-evidence.json` covers only finalized `enclosing-context-mismatch` rows from link hash `sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.

Pinned Xcode `swift-demangle --expand` node trees reconstruct compiler ownership for every row: exact module & full nominal path, including extension module where present. One raw SourceKit entity exists per row; raw kind & effective public access match. Raw context is empty in 33 rows & immediate lexical suffix in 173.

Structural owner bridge result: 173/206 exact & eligible, 33/206 held on explicit lexical-module provenance. All 33 rows have v6 target `SwiftUICore.*` while pinned compiler USR tree says nominal module `SwiftUI`; no alias evidence is assumed. 0 missing expanded trees. 93 owners use `Extension` nodes. Two rows contain generic requirement reference paths & three repeated owner-name references; only direct declaration path is accepted. Function-local owner paths are rejected by control.

Evidence proposes review-only `f1-bridge-206-v2` mapping with every row identity, raw USR, raw context, interface scopes, compiler nominal & extension modules, full path, & controls. Current link promotion remains 0; finalized manifest is untouched. 33 module-alias rows remain held until explicit compiler identity evidence.

Fault controls start from accepted row `SwiftUI:21523 _ViewRepresentation` plus accepted nested extension row `SwiftUICore:9901 FontAttribute`; each baseline passes production validator before raw tree/entity mutation. Controls reject same suffix/different outer, nominal module, extension module, function-local scope, repeated declaration name, duplicate raw entity, missing access, & actor-kind mutation. Generic requirement references remain excluded by node kind while held alias stays rejected. Duplicate USR sections & unknown demangle records fail parser.

Evidence records bridge-source, investigator, toolchain, interface, request, raw-index, demangle-output, & immutable link hashes.

Reproduce:

```sh
python3 factory/catalogue/residual-investigation/bridge_contexts.py
```
