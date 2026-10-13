# Prospective SF Symbol implementation ticket

Original pilot witness remains exact:

`factory/pipeline/pilot-next-source-v1/image-baseline-v1/witness.swift`, SHA256 `4a9c0ad851d32019523ec3a8224073fa93a2ac4e032a87683633870e617f71dd`.

It requests `Image(systemName: "star.fill")`, `.resizable()`, `.scaledToFit()`, 32x32 frame, yellow foreground, light scheme. Current runtime `37429120` already preserves `ImageReference.system(String)` & `ImageReference.named(String)` in `Controls.swift:50-77`, resolves image nodes in `Graph.swift:705-705,1690-1747`, & emits image accessibility role through current graph resolution. Current bridge ABI 0.6 provides only retained RGBA `ImageHandle`, `registerImage(width:height:rgba:stride:)`, `Primitive.image`, & release (`SwiftRightBridge/Types.swift:56-70`; `Bridge.swift:351-367`). It has no SF Symbol catalogue, glyph path, symbol weight, or platform-independent symbol raster API.

Required protected changes after SR0 closure:

1. Define source-bound symbol provider contract: name `star.fill`, point size 32, weight/design, foreground RGBA, scale, raster/path version, exact provider identity, & deterministic bytes or path hash. Unknown names fail closed; no named-asset/default substitution.
2. Extend bridge ABI beyond `image_register` with a versioned symbol registration or path primitive carrying provider identity, dimensions, scale, & release semantics. Preserve existing ABI 0.6 image handles & add capability negotiation before use.
3. Add renderer provider on Windows that consumes approved symbol bytes/path with explicit sampling & color semantics. A Windows SF Symbol catalogue or glyph mapping must be licensed/source-bound; DirectWrite fallback is not equivalent evidence.
4. Add factory host `FactorySymbolRegistry` with one retained handle per `(name, size, weight, design, color, scale)`, stdout registration/provider identity, release on window close, & fail-closed unknown symbol handling.
5. Extend Mac source capture to emit same provider identity, raster/path hash, image bounds, & pixel evidence; qualify only after Mac/Windows same-source rows, screenshot crop, UIA role/name, handle lifecycle, & parity joins.

Until these changes are reviewed after SR0 closure, original `star.fill` remains held on `sfSymbolProvider`; v2 named RGBA asset is separate source evidence.
