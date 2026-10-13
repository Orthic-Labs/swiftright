# Image source adapter v1 — prospective named RGBA route

Existing Image pilot source is `factory/pipeline/pilot-next-source-v1/image-baseline-v1/witness.swift`, exact SHA256 `4a9c0ad851d32019523ec3a8224073fa93a2ac4e032a87683633870e617f71dd`; it requests `Image(systemName: "star.fill")`. Existing Windows image plan explicitly holds because ABI 0.6 has `image_register` but no SF Symbol catalogue/provider. No `star.fill`→glyph mapping is proposed.

This packet supplies separate runnable prospective asset source using `Image("sr1.rgba.checker")`, an exact source-owned 2×2 RGBA8 image. It uses measured bridge APIs `Bridge.registerImage`/`Bridge.release` & ABI primitive `.image`; no platform asset lookup or symbol substitution.

Files:

- `original-star-fill-Witness.swift`: untouched original pilot witness, source hash above; remains held.
- `asset-Witness.swift`: named-asset candidate, SHA256 `ce5f98509a95a62b698fd16b4d01b3eea7995101d7aa5c2db7fb0cafd31df88e`.
- `FactoryImageAsset.swift`: bounded 2×2 RGBA store, SHA256 `9581980d63ed0b13ba268edabf5f9cf1f600425f8434dce31caaa475e764b69f`; bytes hash `c21b35e3f28e676cedf24c13575a7346682e101a2d26aad9598d0cdbcee9ee3b`.
- `main-image-route.patch`: adds Image node handling, register/release lifecycle, asset witness selection, & removes only SF-symbol provider hold for this asset candidate; SHA256 `a2d2a04057ebd824754182515550057ed59693ce95246b1659e67154b5366ca9`.
- `adapter-inputs.json`: exact pins, paths, required channels, & pending measurements.

## Measured route basis

Runtime `ImageReference.named` is implemented at `factory/native/windows/api-source-22172ff2-20261011/runtime/Sources/SwiftRightRuntime/Controls.swift:50-77`; resolved Image nodes expose `ResolvedNode.image` at `Graph.swift:670-672`. Bridge ABI 0.6 declares `ImageHandle`, `.image(ImageHandle, Rect, radius:)`, `Bridge.registerImage(width:height:rgba:stride:)`, & `Bridge.release` in `factory/native/windows/remaining-five-hosts-v2/dependencies/staged-bridge-inputs-r09/Sources/SwiftRightBridge/{Types.swift,Bridge.swift}`. Existing Windows host currently has no `case "Image"` branch & returns unsupported node, so patch is required.

## Root staging

Stage packet files as fresh package sources under `Sources/FactoryProbe/`, apply `main-image-route.patch` to existing measured Image host package, keep runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` & renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, then use existing bounded Image planner `factory/pipeline/pilot-next-source-v1/image-baseline-v1/windows-capture-v1/prepare-image-windows-plan-v1.py`. Its final invocation requires measured `--case` & `--expected-host-hash`; leave plan/case/tuple/receipt/EXE/native values pending until root runs fresh count1 then count20.

Original `star.fill` pilot remains held on `sfSymbolProvider`; named RGBA candidate still needs fresh layout, provider/paint, screenshot, UIA, source/runtime/bridge joins, retained-handle, owned-exit, & native parity evidence.
