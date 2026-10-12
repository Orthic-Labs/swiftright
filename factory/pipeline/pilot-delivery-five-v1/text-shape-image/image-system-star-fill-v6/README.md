# Windows star.fill live-provider source packet v6

This packet preserves original `Image(systemName: "star.fill")` witness. Mapping declares Segoe Fluent Icons E735 as explicit substitute provider; no SF Symbol parity claim is made. Historical r4 producer bytes remain under `provider-evidence/` for provenance only.

`FactorySystemImageRegistry` reads bounded provider declarations, resolves names through table, derives target size & tint from current runtime image frame, then calls shared `FactorySystemImageProvider`. Provider creates process-local Segoe Fluent Icons font handle, calls WinSDK GDI `GetGlyphOutlineW` with `GGO_GRAY8_BITMAP`, converts live coverage to target RGBA, registers ABI 0.6 image handle, & releases font/DC handles. No cached RGBA sidecar, Mac fixture pixels, or expected-pixel gate is read by runtime. Logs include provider identity, glyph, source/target bounds, tint, coverage, & GDI font metrics.

Mac source packet `image-system-star-fill-v1/mac-source` retains fixed 320x240 `topLeading` root. Windows packet retains full-client 320x240 proposal & top-leading placement; no centering transform is added. Root must report actual RGBA differences after native build/capture.

## Provider-success boundary

Provider success means one native run logs `rasterization=live-gdi-getglyphoutlinew`, declared name `star.fill`, glyph `E735`, nonzero source coverage, current target dimensions & tint, successful ABI image registration, and clean handle release. It proves live GDI rasterization for declared substitute policy only; it does not prove SF Symbol geometry, coverage, bounds, color, or pixel parity. A capture comparison must report those separately.

Current source has no fallback path: `FactorySystemImageRegistry.handle` propagates provider errors, while `factorySystemImagePrimitive` propagates registry errors. This is required for honest failure. `CreateFontW` requests `Segoe Fluent Icons`, but v6 does not verify selected face with `GetTextFaceW` or prove font-file identity; a successful glyph call therefore establishes rendered coverage, not exact face identity. Native logs must retain provider identity & observed metrics, with any face-selection uncertainty recorded.

Compile-risk review is source-only. WinSDK signatures used by v6 are `CreateCompatibleDC`, `CreateFontW`, `SelectObject`, `GetTextMetricsW`, and `GetGlyphOutlineW`; `MAT2`/`FIXED` construction and optional GDI handles are the only unverified interop points in this checkout because no local Windows WinSDK declaration snapshot is present. No compile claim is made until root's supervised Windows build. GDI gray8 rows are explicitly converted bottom-up to top-down RGBA; this conversion needs native evidence, not parity assumption.
