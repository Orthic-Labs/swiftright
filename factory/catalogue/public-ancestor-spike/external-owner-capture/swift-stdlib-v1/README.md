# Swift standard-library owner capture v1

Bounded F1 raw capture for exact Swift nominal owners referenced by UI/Core source headers: `Optional`, `Never`, numeric fixed-width types, `RangeReplaceableCollection`, & `MutableCollection`.

`swift-stdlib-evidence.json` records pinned Swift.swiftinterface declarations, top-level nominal ancestry, public/read access, inline attributes, conditional stack, SwiftUI/SwiftUICore extension header rows, dedicated SourceKit reference kind/name/USR/line/column, demangle output, immutable compiler-cursor link, tool hashes, request, raw index, exits, & stdout/stderr hashes.

Capture makes no eligibility or promotion decision. Missing direct UI/Core extension rows remain raw unknown status; graph absence is never interpreted as exclusion.

Verify with:

```sh
python3 factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-v1/verify_swift_stdlib.py
```
