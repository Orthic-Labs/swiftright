# F2 public source binding v1

`manifest-usr-v1.json` is exact ten-block copy of pinned registry manifest, with every symbol selector validated as `usr:<exactUSR>` against pinned 108272-symbol catalogue `sdk.macos27.swiftui`. Current source manifest already used USR selectors, so resolution records 65 revalidated USR selectors & zero path selectors; no fields/status/progress were promoted.

`registry-resolution.json` is produced by production `factory.registry.registry.build_registry` with fixed receipt time. `final-candidate-resolution.json` remains pending until independent final F1 candidate freezes. Unresolved, ambiguous, & hidden selector controls are tested through production resolver. `archive/inputs` preserves base catalogue, manifest, & schema; `archive/tools/registry.py` preserves resolver source.
