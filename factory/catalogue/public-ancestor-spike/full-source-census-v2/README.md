# Full-source census v2

`full-source-census-v2.json` is a raw lexical/source-index census for installed SwiftUI & SwiftUICore interfaces from Xcode 27.0 (27A266), SDK 27.0, target `arm64-apple-macosx27.0`. It preserves every parser-emitted source start, lexical owner chain, extension target spelling, explicit access token, conditional frame, declaration attributes, and raw SourceKit entity observation. Original interface bytes, index streams, requests, Core receipt/tool metadata, v12 input, and immutable 836 link are copied under `raw/` & hash-pinned.

Before initial capture, parser/helper source copies were frozen under `source-snapshot/`: `lexical_model_v2.py` (SHA-256 `cc6d4dab563f713b91c0ef1f29cbb214a3c129c8f5f3823f438ac24aef75cdd6`) & `exact_validator.py` (SHA-256 `83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5`). `strict_match.py` is preserved in same snapshot but not executed by capture. `pre-capture-manifest.json` pins all parser/helper, source, request, receipt, and raw-index files plus capture source before output generation. Original live-SDK validation source/output are frozen in `live-sdk-validation/`; initial capture verified installed interface bytes against archived copies. Current capture replay consumes only `raw/`, `source-snapshot/`, & that pinned live-validation receipt; it never reads installed SDK paths or caches. Capture rejects modified archived bytes or live-validation receipt.

Reproduce census with:

```sh
PYTHONDONTWRITEBYTECODE=1 factory/.venv/bin/python factory/catalogue/public-ancestor-spike/full-source-census-v2/capture.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/catalogue/public-ancestor-spike/full-source-census-v2 factory/.venv/bin/python factory/catalogue/public-ancestor-spike/full-source-census-v2/test_capture.py
```

The focused tests replay output, verify altered pre-capture-manifest/source pins fail closed, & confirm capture succeeds with installed SDK paths unavailable.
`SHA256SUMS` pins every captured file in this folder except itself; from this directory, verify with `shasum -a 256 -c SHA256SUMS`.

Observed counts: 20,443 lexical declaration starts, including 2,597 extension headers & 17,846 nonextension starts; 2,386 nominal scopes. All 12,635 v12 rows map one-to-one to source starts: 12,602 match exact module/line/family/name; 33 have one source start at exact module/line/family but source-spelled name differs, retained in `v12LineageJoins`. The remaining 5,211 nonextension starts are additional source census records beyond v12. No same-family ambiguity or unaddressed v12 row was observed. This does not establish equivalence of names or compiler identity for those 33.

SourceKit streams contain 19,185 raw entities for SwiftUI & 836-lineage SwiftUICore (10,679 + 8,506), also 19,185 for SwiftUI & fresh header-correct SwiftUICore (10,679 + 8,506). Both Core captures are retained separately because access fields differ; fresh request records `-module-name SwiftUICore`, `-public-module-name SwiftUI`, & `-module-abi-name SwiftUI`. Each stream retains full parsed entities & raw bytes.

Status intentionally remains `raw-census-only-no-universal-swift-grammar-or-public-api-completeness-claim`. Parser enumeration covers constructs emitted by pinned parser; counts do not prove complete Swift grammar coverage, all compiler-generated declarations, SDK API eligibility, or public ancestor eligibility. Raw source/API classifications belong to separately reviewed production proof.
