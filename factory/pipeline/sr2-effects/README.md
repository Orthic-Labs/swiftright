# SR2 effects (issue #54)

Eight cases for the effects the S1 notch uses, in `swiftui.effects/`. They are listed in `factory/pipeline/ci-lists/issue54-effects.txt`. None has run yet: every gate that is not the default one says why.
Built from the existing templates by copying `sr2-r4/.../brightness-v1` (static), `sr2-r3/.../bouncy-v1` (manual clock) and `sr2-text/.../styled-runs-v1` (text); only the witness and `pair.json` are the case's own, and the Windows host sets `painter?.usesRendererPaths = bridge.supportsPaths` as the other SR2 cases do.

| Case | What it decides | Gate |
| --- | --- | --- |
| brightness-pixel-v1 | `.brightness` on colours and shapes, exact: amounts are whole levels (0.2 x 255 = 51) | default; Mac side through `ImageRenderer` (`cacheDisplay` skips the filter, CI 39409471434) |
| brightness-image-v1 | `.brightness` on 1:1 bitmaps, exact | default; `ImageRenderer` |
| scale-nonuniform-v1 | `scaleEffect(x:y:)` and `scaleEffect(CGSize)` stretch fills: elliptical capsule ends, ellipse from a circle | F-path edge statistics on the curved edge band (provisional) |
| paint-colour-v1 | colour interpolation of a shape fill, a Color view, a circle and a foreground-style fill; the mid frames tell gamma-encoded from linear-light blending (153 against 187 in red at 0.5 s) | exact interiors; edge statistics for the circle only |
| paint-linewidth-v1 | stroke width 2 -> 10 pt with the colour | exact interiors; edge statistics for the ring |
| spring-removal-v1 | an interrupted bouncy spring is removed by the one-pixel tolerance rule, not early | clock gate, 1 px |
| tint-controls-v1 | `.tint(.red)` on a prominent Button, switch, checkbox, Slider and ProgressView | default (first pair fits the tint mapping) |
| minimum-scale-v1 | `minimumScaleFactor` shrink to fit and truncation after shrinking | text colour and position gates (provisional tolerances) |

## Known limits, not covered here

- A stroke under a non-uniform scale is widened by the geometric mean of the two factors, not per axis (the rasteriser strokes in device space); scale-nonuniform-v1 therefore uses fills only.
- Text under a non-uniform scale keeps the uniform (geometric mean) size, as under a uniform scale.
- Colour interpolation is gamma-encoded until paint-colour-v1 says otherwise: `ColorInterpolation.space` in the runtime is the one switch.
- A semantic colour against a different semantic colour (or an `rgba`) cannot be blended in the runtime (the host resolves the names): it takes the new colour at once.
