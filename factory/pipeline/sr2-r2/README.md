# SR2 R2: Animatable shapes (issue #37)

Block R2 of the SR2 plan (`docs/sr2-plan.md`): `Animatable`, `VectorArithmetic`, `AnimatablePair` and `EmptyAnimatableData` on shapes. A shape's geometry is interpolated per tick and `path(in:)` is re-run.

## Cases (`swiftui.animatable/`)

These are manual-clock cases built from the block 18 clock template (`blocks-6-10/swiftui.animation/default-spring-v1`). Each one compares every clock frame Mac against Windows, and each frame is gated with the F-path curved-edge statistics.

- **trim-linear-v1:** the ring gauge. `Circle().trim(from: 0, to:)` goes from 0.1 to 0.9 under linear 1 s, with a round-cap stroke.
- **custom-pair-v1:** a user `Shape` whose `AnimatablePair` animatableData is a notch-like neck (width and depth), under easeInOut 0.6 s.
- **corner-radius-v1:** `RoundedRectangle(cornerRadius:)` from 4 to 40, circular style, under linear 1 s.
- **inset-v1:** `Circle().inset(by:)` from 0 to 30, under linear 1 s.

No spring cases: on the Mac's manual clock a spring's value depends on how often it is sampled (decision C4). The R3 spike replaces the runtime's spring model with SwiftUI's exact integrator, and R3 adds the spring cases.
