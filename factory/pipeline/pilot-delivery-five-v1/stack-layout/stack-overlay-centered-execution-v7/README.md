# Centered ZStack/overlay execution source packet v6

Fresh source packet derived from v5. Original Witness.swift bytes, runtime/bridge/renderer tuple, intrinsic subtree centering, background policy, & ABI 0.6 joins remain unchanged. `FactoryResolvedNodeMapper.swift` is copied from shared-windows-host and replaces only inline node paint dispatch; per-witness Graph construction remains `Graph(Witness_stack_overlay())`.

Shared sources: `../shared-windows-host/FactoryFill.swift` & `../shared-windows-host/FactoryResolvedNodeMapper.swift`. Mapper consumes resolved node geometry/style and preserves unsupported provider/geometry errors; it does not substitute pixels, offsets, or runtime behavior. Root must reseal operational stage then perform existing bounded build/capture.

Mac diagnostic source is under `mac-source/`. It preserves original witness paint, then records public macOS 15 `TextRenderer` typographic bounds for separate bare `Text("+")` probe. Family/point-size provider metadata is unavailable from public API.

## Default-text diagnosis

Root observation `root-execution/stack-overlay-typography-v6-mac-r1/observation.json` records Mac bare `+` width `8.1123046875` DIP, run ascent `12.568359375`, descent `2.7421875`, leading `0.689453125`, line rect `8.1123046875 × 16` DIP. Provider family/point-size metadata is unavailable through public `TextRenderer` API.

Runtime source preserves this distinction: `LayoutEngine.measureText` falls back to `Font(id: "body")`, then forwards `fontMetadata` (nil for this legacy bare text) in `TextMeasureRequest`; ABI 0.6 already carries family, weight, size, line height, scale, and width. Default font policy therefore belongs at factory `TextMeasurer`/bridge boundary, not in runtime layout, renderer, or witness coordinates.

Current Windows `package/Sources/FactoryProbe/main.swift` instead accepts only `fontID == "body"` with nil metadata, then hardcodes `Segoe UI`, size `16`, and line height `24`. Captured output is `27.363281 × 60` pixels at scale `2.5` (`10.9453125 × 24` DIP), so observed placement differences are font-provider policy evidence, not a justified coordinate correction.

Smallest behavior correction is one shared factory host font-policy resolver: map legacy `body` plus nil metadata to measured Windows default family, weight, point size, and line height; pass those values through existing ABI 0.6; preserve explicit `Font.Metadata` and line-limit semantics; fail closed when provider selection is unavailable. Do not derive policy from this single glyph or replace runtime font metadata with fixture coordinates. This packet records diagnosis only; root must compile & capture fresh host source after policy implementation.
