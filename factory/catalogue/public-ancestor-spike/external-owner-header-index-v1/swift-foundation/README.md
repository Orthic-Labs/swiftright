# Swift/Foundation external-owner header indexes v1

Whole immutable SDK SourceKit indexes captured for exact F1 targets: 16 Swift owners (`Optional`, `Never`, numeric integer/floating types, `RangeReplaceableCollection`, `MutableCollection`) & 4 Foundation owners (`AttributedString`, `AttributeScopes`, `FormatStyle`, `AttributeDynamicLookup`).

Each module preserves source/header rows, shlex-derived compiler arguments, production target, removed variants, frontend forwarding, exact request preimage, process argv/cwd/exit, raw stdout/stderr, tool hashes, & target physical line/name/kind/USR/effective-access records. Top-level nominal ancestry is explicitly `[]`; no eligibility or public inference is made.

Counts: Swift 13,629 declaration records; Foundation 11,927. All target records have public effective access & unique physical identity pairs. Swift initial raw-flag failure remains frozen under `attempts/`; corrected request forwards frontend-only flags through `-Xfrontend`.

Verify with:

```sh
python3 factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/swift-foundation/verify_swift_foundation.py
```
