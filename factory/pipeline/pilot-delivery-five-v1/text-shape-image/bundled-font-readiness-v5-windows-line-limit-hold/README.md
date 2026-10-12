# Windows Tinos host packet v5 — line-limit ABI hold

This packet preserves v4 witness bytes, Tinos-Regular resource, runtime, renderer, bridge, metrics source, & registration checks. It adds one fail-closed adapter rule: any `TextMeasureRequest.lineLimit` is retained as an explicit policy input, then rejected because ABI 0.6 `swr_measure_request` has no line-limit or truncation field. No text cropping, substring replacement, width trick, fixture bitmap, or metric override is used.

ABI evidence is pinned in `package/../runtime-source-*` & bridge inputs: `MeasureRequest` exposes text, family, locale, weight, color, font size, line height, scale, & max width only. Renderer `swr_measure_text` shapes all wrapped lines; it has no line-limit policy. Therefore Tinos witness remains held until protected ABI/renderer adds exact line-limit semantics.

Witness remains exact: `Font.custom("Tinos-Regular", size: 18)`, `.lineLimit(1)`, width 128, text `SwiftRight bundled Tinos font witness`. Resource remains `package/Resources/Tinos-Regular.ttf`, 521588 bytes, `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`. Renderer selection remains `unproven`.

Source-only packet. Root owns any future compiler/native work after ABI support exists.
