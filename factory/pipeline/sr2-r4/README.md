# SR2 R4: scale and colour effects (issue #39)

- **scale-center-v1, scale-anchor-v1, scale-nested-v1:** static `scaleEffect`, using the R1 static template. Gated with the F-path edge statistics, because scaled edges land on fractional device pixels.
- **brightness-v1:** static `brightness`. Default gate: colours must be exact outside the 1 px edge band.
- **scale-animated-v1:** an animated `scaleEffect(x:)` about `.leading`, linear over 1 s on the manual clock. Clock gate on the bar's painted extent.

These cases contain no text, because scaled text is R4b. `tint` has no pixel case: S1 has nothing under its tint, and unit tests cover the `.tint` style.

## Findings from CI 39409471434

- **brightness-v1 is not in the CI list.** The Mac capture host draws through `cacheDisplay`, which does not apply SwiftUI's brightness filter: the Mac reference showed the colours unchanged. `ImageRenderer` does apply it, and that is where the rule was measured (add the amount to each sRGB channel, then clamp). Brightness is verified by unit tests against those measured values. The case stays here for a Mac host that renders through ImageRenderer.
- **Non-uniform scale is a limitation.** SwiftUI scales the shape's geometry (a capsule under `scaleEffect(x: 2, y: 0.5)` gets elliptical ends), while the host redraws the shape at the new size with radii scaled by the geometric mean. Every use in S1 is uniform, so scale-nested-v1 now uses uniform factors.
- **Off-grid strokes.** A stroke whose bounds are not on whole device pixels now takes the path raster: the renderer's bordered rect lost about 2 px on a scaled ring.
- **scale-animated-v1** is compared frame by frame as pixels: `scaleEffect` does not move the layout frame that the clock gate tracks.

## Findings from CI 39411214255 and 39413123283

- Shapes and solid rects under a scale are anti-aliased between pixels on the Mac. The host now draws them with the unsnapped path raster, and the rounded rect matches.
- A **stroked** ring under `scaleEffect(1.4)` is still about 1 px smaller in diameter on Windows (right edge 456 vs 457 px, top 313 vs 312) with sharper edges. The cause is open (issue #44). scale-center-v1 now uses a filled circle.
