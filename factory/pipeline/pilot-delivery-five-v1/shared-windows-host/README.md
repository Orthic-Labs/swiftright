# Shared Windows capture host

Every pilot case package is now a plain **Witness + capture host**. `CaptureHost.template.swift` owns only the capture lifecycle (owned window metrics, activation veto, background, optional centring, 10 s lease, renderer DLL from `SWIFTRIGHT_RENDER_DLL`). All painting is the product's: `packages/SwiftRightHost` (`ResolvedNodePainter`, `ShapePainter`, `SystemImageRegistry` + shipped symbol table, `BridgeTextMeasurer`; bundled fonts through `BundledFontLibrary` in `packages/SwiftRightBridge`).

- `stamp-case.py` / `stamp-all.sh` write `main.swift`, `FactoryViewport.swift` and `Package.swift` into each case and delete the former per-case adapters (continuous shape adapter, system-image provider/registry/assets, font adapter, body-font adapter, mapper, fill/geometry helpers). `Witness.swift` is never touched.
- `Package.swift` depends only on the product; `@@PRODUCT_STAGE@@` is replaced by `pair.py --stage <name>` (`factory/tools/stage-product.py`: one `git archive` of runtime + bridge + SwiftRightHost for all cases).
- Per-case source-binding / plan / receipt JSON files predate this move and still describe the old host sources; they are historical provenance, not current bindings.
