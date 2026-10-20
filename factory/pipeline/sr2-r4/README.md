# SR2 R4: scale and colour effects (issue #39)

- **scale-center-v1, scale-anchor-v1, scale-nested-v1:** static `scaleEffect`, using the R1 static template. Gated with the F-path edge statistics, because scaled edges land on fractional device pixels.
- **brightness-v1:** static `brightness`. Default gate: colours must be exact outside the 1 px edge band.
- **scale-animated-v1:** an animated `scaleEffect(x:)` about `.leading`, linear over 1 s on the manual clock. Clock gate on the bar's painted extent.

These cases contain no text, because scaled text is R4b. `tint` has no pixel case: S1 has nothing under its tint, and unit tests cover the `.tint` style.
