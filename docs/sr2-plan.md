# SR2 plan: Pulse notch slice S1 (notch face with ring gauges, read-only)

Accepted 20 October 2026 (Sage design, lead decision). Source: docs/pulse-notch-demand-map.md (S1 = J01 + J03, 15 SwiftUI files). F-path (vector paths, rotationEffect for shapes) is delivered (#35). A compile probe against the runtime found the remaining S1 APIs missing; the hub port had stubbed them as no-ops (probes/sr1-pulse-probe/stubs/GapsModifiers.swift).

| Block | APIs | Layer | Gate | Est. h |
|---|---|---|---|---|
| R1 compose/place | Group, ViewModifier + .modifier, background, offset, position, GeometryReader, allowsHitTesting | runtime layout; host hit-test | exact pixels + semantic frame tree; hit-test via the block 38 harness | 6 |
| R2 Animatable | Animatable, VectorArithmetic, AnimatablePair on Shapes (path(in:) re-evaluated per tick) | runtime interpolation; host re-raster (F-path) | block 18 clock gate + F-path edge gate on sampled frames | 10 |
| R3 springs | spring(response:dampingFraction:), spring(duration:bounce:), .snappy, .bouncy, delay | runtime Animation/SpringModel; integrator fitted on a Mac manual clock | clock gate (C3, C4, C11) | 10 |
| R4 scale/colour | scaleEffect (uniform, anchor), brightness, tint | host fold (rects, radii, strokes, raster size; text at font size x s); tint in the environment | text position gate, pixels, clock gate | 8 |
| R5 text | minimumScaleFactor, monospacedDigit (OpenType tnum via ABI 0.8 features) | runtime text measurement | text position gate | 5 |
| R6 clip/adapted | clipShape (mask for host-rasterised content, rect clip for text runs), glassEffect/Glass (Adapted: solid, documented gap; Mac references in headlessGlass mode), contentTransition(.numericText()) (rolling digits inside a transaction, #55) | host | pixels + semantic, named gaps | 8 |

No ABI revision for S1. ABI 0.12 (path table) stays deferred; its triggers now also include a static frame that partially clips text, and rotated text. GPUI 0.2.2 carries a full transform only for monochrome sprites and clips by rectangle only (scene.rs, window.rs), so real affine/path-mask rendering would mean patching GPUI shaders. Order: R1, then the R3 integrator spike, R2, R3, R4/R5, R6. Outside SwiftRight and blocking S1 end to end: the Mac carve-out and Observation rewrite (demand map lines 805-809).

**R3 integrator spike (20 October): done.** SwiftUI steps every built-in spring with semi-implicit Euler at 1/300 s (ω = 2π/duration, ζ = 1 − bounce, or 1/(1+bounce) below 0; response/dampingFraction map directly; `.snappy` 0.15, `.bouncy` 0.3), reproduced to 5e-8 at real cadences; `interpolatingSpring` is closed form. Removal timing is still open. Details, sampler and data: `factory/pipeline/sr2-r3-spike/SPIKE-RESULT.md`.

## Status, 20 October: S1 blocks delivered

- **Delivered.** R1 (#36), R2 (#37), R3 (#38), R4 (#39), R5 (#40), R6 (#41) and R4b scaled text (#42). Each passed its Mac-vs-Windows CI cases at N=20 and an Oracle review. Evidence is in docs/sr1-status.md (the 20 October entries).
- **Follow-ups, outside the S1 plan:**
  - #43: text and bitmaps under a non-rectangular clip are clipped to its bounds. A true mask needs a renderer alpha/path clip, which belongs with the deferred ABI 0.12.
  - #44: half-pixel layout under `scaleEffect`. Widths and main-axis snapping are fixed; a sub-pixel offset remains on a later stack child, pending a study of stacked tie rules.
- **Not modelled, documented:**
  - SwiftUI's removal rule for parameterised springs;
  - non-uniform scale;
  - brightness on bitmaps;
  - tinted controls;
  - glass (adapted);
  - `contentTransition` (adapted).
- **Still blocking S1 end to end, outside SwiftRight** (demand map): the Mac carve-out and the Observation rewrite.

## Adapted APIs revisited (issue #55, 21 October)

- **`contentTransition(.numericText(countsDown:))` and `.numericText(value:)`: implemented.** Inside an animation transaction a Text rolls its changed glyphs: old and new strings are aligned from the trailing end (place value), an unchanged glyph stays and slides to its new place, a changed one leaves up while its replacement comes from below (reversed when counting down, or when `value:` fell since the last change), and each glyph is clipped to the line box. The roll is a presented channel of the node (`PaintValues.roll`) so it follows any animation, a spring's overshoot is clamped and an interrupting change restarts from the shown glyphs. Without a transaction the text swaps at once. Wrapped, truncated, multi-line and styled-run Texts swap at once. Unmeasured: SwiftUI's exact travel distance and fade curve (one line height, linear fade here); `numeric-text-v1` is the first evidence. Code: `NumericTextRoll.swift`, `ResolvedNode.numericRoll`, `ResolvedNodePainter.emitNumericRoll`.
- **`glassEffect`: stays adapted (no material), decided with evidence.**
  - A real glass is a blur of what is behind the view. GPUI 0.2.2 has no backdrop blur: `blur_radius` exists only for shadows (scene.rs, style.rs) and the shaders have no sampling of the framebuffer.
  - The only blur GPUI offers is window-level: `WindowBackgroundAppearance::Blurred` (platform.rs; Windows implements it as accent state 4, acrylic behind the whole window, platform/windows/window.rs:770). That fits a window whose whole background is glass (the notch) and nothing smaller.
  - `swr_run_options` (render/swiftright-abi/include/swiftright.h, flags and the 0.10 tail) carries no background or backdrop option, so option (c) needs an ABI addition and a renderer change (outside this scope). Needed: a `swr_run_options.flags` bit (for example SWR_RUN_BACKDROP_BLURRED) mapped to `WindowOptions.window_background = Blurred` plus a transparent clear colour, and the host painting no opaque root fill; the runtime would report "glass applied to the root background" on the resolved root. Not done: it also needs an acrylic tint pass against a Mac reference, and the notch design (solid on Windows, pulse/docs/settings.md) does not ask for it.
  - Decision: keep the adaptation (the view is drawn as without the modifier); no pixel case, because a Mac comparison would only measure the adaptation (Mac references use headlessGlass).
- **33 pt switches to the Display optical size: intended, not a bug.** SF is one variable font with a continuous optical-size axis (SFNS.ttf on macOS 27: opsz 17 to 96, default 28), so SwiftUI text at 33 pt is already shaped at an optical size near its Display end. Segoe UI Variable has three named instances (Small 8, Text 10.5, Display 36) and gpui cannot vary opsz (G11), so the host picks the nearest by log distance (`SegoeOpticalFamily`, decision G70): the Text/Display boundary is 25.9 DIP, so 33 DIP is Display and 25.5 DIP is Text. The step is the instance snapping, not a mismatch of the switch point. Whether SF's Text/Display switch sits at 20 pt as a named-family rule is not verified here (only the axis range was read from the installed font).

