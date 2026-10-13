# Image host package v2: explicit Mac-matched sampling

This fresh packet keeps v1 witness, 4x4 RGBA bytes, named asset, bridge image handle lifecycle, fixed 320x240 top-leading viewport, current runtime `37429120`, bridge `0a745ab`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, & canonical Windows paths. v1 remains immutable.

Mac source capture for same `Image("factory.rgba.square.v1")` witness reports interpolated quadrant boundaries. v1 Windows adapter expanded source with nearest neighbour, producing hard 8-pixel bands. v2 uses deterministic center-sampled bilinear interpolation on opaque sRGB channels before `Bridge.registerImage`; renderer-side filtering remains independently measured.

Source PNG is 4x4 RGBA8, SHA256 `57b45fdbc5d9a86bbad5f547b6964e39ba0c872130c564877d306f61477f6bea`. Raw RGBA payload SHA256 is `dc3ae926d85afbeca3cc60a12a8c69faad0f0b31f60c76ebe55bf4be00aab008`. Sampling maps destination center `(x+0.5,y+0.5)` to source `(u,v)=(center/8)-0.5`, clamps edges, then bilinearly rounds each channel. Expected pixels are recorded in `sampling-reference.json`.

Root staging uses `tools/prepare-bounded-stage.ps1 -Host image-v2`, fresh destination `.factory-work\hosts\image-v2\package`; root must supervise compile at 1 GiB, one SwiftPM job, one frontend thread. Exact argv is emitted by `tools/compile-bounded.ps1`.

Root comparison: capture Mac same-source PNG & Windows native screenshot, crop same 32x32 image rectangle using top-leading geometry, compare RGBA pixels against `sampling-reference.json` & report image-handle register/release rows. Preserve renderer-selection, DPI, screenshot, UIA, retained-handle, owned-exit, & native-parity holds until fresh receipts.

`sf-symbol-ticket.md` records protected API work for original `Image(systemName: "star.fill")`; v2 does not substitute SF Symbol with named asset.
