# Next ABI 0.6 pilot proposals

These are source proposals only. They reuse existing capture, UIA, pixel, stream, memory, and archive protocols; they require fresh case, tuple, compiler, and host receipts. No image renderer or bridge ABI change is proposed.

## `swiftui.text.layout.baseline`

Witness renders `Text("Aa")` with fixed system font, fixed foreground color, and fixed frame. Independent channels are root geometry, compositor pixels, text observation, and source-bound compile receipt. Mac host can observe baseline/frame; Windows host must prove same font family availability & renderer hash. Holds: font fallback, DPI, text extraction provider, and cross-host baseline parity until measured receipts exist.

## `swiftui.layout.stack-spacing`

Witness renders two fixed `Rectangle` children in `HStack(spacing: 8)` with explicit frame & color. Independent channels are child frames, parent frame, compositor pixels, and source-bound compile receipt. Existing ABI 0.6 geometry/pixel path is sufficient; no image renderer change. Holds: Windows child-frame UIA availability, DPI rounding, compositor occlusion, and provider layout ordering until fresh Count1 then Count20 evidence exists.

Admission for either block requires fresh source/case/tuple IDs, exact compiler/runtime/renderer joins, one successful Count1 proof, then fresh Count20 archive. Historical padding or Rectangle records cannot satisfy admission.
