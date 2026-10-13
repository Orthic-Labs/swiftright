# Centered ZStack/overlay execution source packet v8

Fresh source packet derived from v7. Original Witness.swift bytes, runtime/bridge/renderer tuple, intrinsic subtree centering, background policy, & ABI 0.6 joins remain unchanged. `FactoryResolvedNodeMapper.swift` is copied from shared-windows-host and replaces only inline node paint dispatch; per-witness Graph construction remains `Graph(Witness_stack_overlay())`.

Shared sources: `../shared-windows-host/FactoryFill.swift`, `../shared-windows-host/FactoryResolvedNodeMapper.swift`, & `../shared-windows-host/FactoryDefaultBodyFont.swift`. Windows package keeps byte-identical copy of shared body adapter; live DPI/profile inputs remain selected at runtime. Mapper consumes resolved node geometry/style and preserves unsupported provider/geometry errors; it does not substitute pixels, offsets, or runtime behavior. Root must reseal operational stage then perform existing bounded build/capture.

Mac diagnostic source is under `mac-source/`. It preserves original witness paint, then records public macOS 15 `TextRenderer` typographic bounds for separate bare `Text("+")` probe. Family/point-size provider metadata is unavailable from public API.

## Default-text diagnosis

Root observation `root-execution/stack-overlay-typography-v6-mac-r1/observation.json` records Mac bare `+` width `8.1123046875` DIP, run ascent `12.568359375`, descent `2.7421875`, leading `0.689453125`, line rect `8.1123046875 × 16` DIP. Provider family/point-size metadata is unavailable through public `TextRenderer` API.

Runtime source preserves this distinction: `LayoutEngine.measureText` falls back to `Font(id: "body")`, then forwards `fontMetadata` (nil for this legacy bare text) in `TextMeasureRequest`; ABI 0.6 already carries family, weight, size, line height, scale, and width. Default font policy therefore belongs at factory `TextMeasurer`/bridge boundary, not in runtime layout, renderer, or witness coordinates.

Current Windows `package/Sources/FactoryProbe/main.swift` instead accepts only `fontID == "body"` with nil metadata, then hardcodes `Segoe UI`, size `16`, and line height `24`. Captured output is `27.363281 × 60` pixels at scale `2.5` (`10.9453125 × 24` DIP), so observed placement differences are font-provider policy evidence, not a justified coordinate correction.

## v8 native body policy

`FactoryDefaultBodyFont.swift` maps legacy `body` plus nil metadata through DPI-aware `SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS)` and `lfMessageFont`, using owned-window DPI from `GetDpiForWindow`. It selects that native `LOGFONTW` with `CreateFontIndirectW`, obtains selected family through `GetTextFaceW`, then derives line height from `GetTextMetricsW`. Font size comes from native `lfHeight` converted through owned-window DPI; weight comes from native `lfWeight`. Each selected family, native metric, DPI, scale, and source API is logged before ABI 0.6 measurement. No Mac target, fixture glyph, coordinate offset, or font-family substitute is used. If profile retrieval, font selection, or metrics fail, host exits before graph construction.

`NativeMeasurer` preserves `Font.body` identity and forwards resolved family, weight, point size, line height, scale, and proposed width through existing bridge measurement. Root must compile & capture fresh host source to observe resulting native metrics.
