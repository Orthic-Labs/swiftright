# Centered ZStack/overlay execution source packet v9

Fresh source-only Stack packet derived from v8. `Package.swift`, `main.swift`, `case.json`, `Witness.swift`, recipe inputs, intrinsic-root centering, background policy, bridge ABI 0.6, renderer tuple11, and witness bytes remain unchanged. v9 changes only body-font ownership: `FactoryDefaultBodyFont.swift` is a thin adapter over live `NativeWindowsBodyFont` runtime policy.

Runtime receipt/tree files contain explicit null hashes until root stages current runtime snapshot. Root must regenerate those bindings, update package/source manifests, and reseal packet plan before compile. No compiler/native receipt is claimed here.

Adapter preserves `Font.body` identity & forwards live DPI/profile family, native metrics, DIPs, scale, and source logging through existing ABI 0.6 measurement. DPI tests use physical-pixel conversion `dpi/96`; no Mac metric or coordinate target is embedded.

`source-bindings.json` covers packet source bytes, witness SHA-256 `d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee`, recipe, bridge, renderer, and null runtime joins.
