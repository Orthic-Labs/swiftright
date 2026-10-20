# SR2 R6: clip and adapted APIs (issue #41)

- **clip-circle-v1:** a colour and an oversized stroked ring clipped to a Circle. Both are masked by the clip's coverage.
- **clip-rounded-v1:** three solid colour bands clipped to a rounded rect. Rects that cross the edge are rasterised and masked.
- **clip-animated-v1:** a colour clipped by the R2 `AnimatablePair` neck as it opens, on the manual clock. The clip animates through the shape geometry channel.

Gate: F-path edge statistics. Text and bitmaps under a non-rectangular clip are clipped to its bounding rect only, so no case puts text under such a clip.

**Adapted, no pixel case:**
- `glassEffect` / `Glass`: no material on Windows, where the Pulse notch is solid.
- `contentTransition(.numericText())`: swaps at once.

On the Mac they draw a material and a per-glyph roll that Windows deliberately does not, so a Mac-vs-Windows comparison would only measure the adaptation. Their APIs compile against both SwiftUI and the runtime.
