# SR2 plan: Pulse notch slice S1 (notch face with ring gauges, read-only)

Accepted 20 October 2026 (Sage design, lead decision). Source: docs/pulse-notch-demand-map.md (S1 = J01 + J03, 15 SwiftUI files). F-path (vector paths, rotationEffect for shapes) is delivered (#35). A compile probe against the runtime found the remaining S1 APIs missing; the hub port had stubbed them as no-ops (probes/sr1-pulse-probe/stubs/GapsModifiers.swift).

| Block | APIs | Layer | Gate | Est. h |
|---|---|---|---|---|
| R1 compose/place | Group, ViewModifier + .modifier, background, offset, position, GeometryReader, allowsHitTesting | runtime layout; host hit-test | exact pixels + semantic frame tree; hit-test via the block 38 harness | 6 |
| R2 Animatable | Animatable, VectorArithmetic, AnimatablePair on Shapes (path(in:) re-evaluated per tick) | runtime interpolation; host re-raster (F-path) | block 18 clock gate + F-path edge gate on sampled frames | 10 |
| R3 springs | spring(response:dampingFraction:), spring(duration:bounce:), .snappy, .bouncy, delay | runtime Animation/SpringModel; integrator fitted on a Mac manual clock | clock gate (C3, C4, C11) | 10 |
| R4 scale/colour | scaleEffect (uniform, anchor), brightness, tint | host fold (rects, radii, strokes, raster size; text at font size x s); tint in the environment | text position gate, pixels, clock gate | 8 |
| R5 text | minimumScaleFactor, monospacedDigit (OpenType tnum via ABI 0.8 features) | runtime text measurement | text position gate | 5 |
| R6 clip/adapted | clipShape (mask for host-rasterised content, rect clip for text runs), glassEffect/Glass (Adapted: solid, documented gap; Mac references in headlessGlass mode), contentTransition(.numericText()) (Adapted: instant swap) | host | pixels + semantic, named gaps | 8 |

No ABI revision for S1. ABI 0.12 (path table) stays deferred; its triggers now also include a static frame that partially clips text, and rotated text. GPUI 0.2.2 carries a full transform only for monochrome sprites and clips by rectangle only (scene.rs, window.rs), so real affine/path-mask rendering would mean patching GPUI shaders. Order: R1, then the R3 integrator spike, R2, R3, R4/R5, R6. Outside SwiftRight and blocking S1 end to end: the Mac carve-out and Observation rewrite (demand map lines 805-809).
