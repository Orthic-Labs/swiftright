# SR2 R3 integrator spike: SwiftUI built-in springs (20 October 2026)

Question (docs/sr2-plan.md, R3): how does SwiftUI evaluate `spring(duration:bounce:)`, `spring(response:dampingFraction:)`, `.snappy`, `.bouncy`, `.smooth` and `interpolatingSpring`, so the runtime can reproduce any of them instead of the single measured table (`SpringModel.table`, decision C4)?

## Method

`sampler.swift` (macOS 27.0.1, 26A434, run from the internal disk, invisible window, no Dock icon, about one second): a `CustomAnimation` receives one fresh `AnimationContext<Double>` from SwiftUI and evaluates 11 animations from copies of it with `Animation.animate(value: 1.0, time:context:)`, from rest, at cadences of 12.5 ms, 1 ms, 100 ms and 0.25 ms, until the animation returns nil (removed) or 2 s. Output: `samples.jsonl` (44 rows). The 12.5 ms default row reproduces `SpringModel.table` to every printed digit.

## Result: the curve (exact)

`model.py samples.jsonl` reproduces every integrated spring to **5e-8** (float printing) at 1 ms, 12.5 ms and 100 ms cadences:

- **Integrator:** semi-implicit Euler at a fixed **H = 1/300 s** (`v += (k(1-x) - c v) H; x += v H`, unit mass). A call at time `t` has taken every step that ends strictly before `t` (`while acc + H < t`, with `acc` accumulated as `acc += H`). The value is held between steps. This explains C4's "constant over 3 ms runs" and its sampling-cadence dependence (only at exact step boundaries).
- **Parameters:** `spring(duration: d, bounce: b)`: ω = 2π/d, ζ = 1 − b for b ≥ 0 and 1/(1 + b) for b < 0, so k = ω² and c = 2ζω. `spring(response: r, dampingFraction: f)`: ω = 2π/r, ζ = f. `.default` = `.smooth` = `.spring` = (0.5, 0); `.snappy` = (0.5, 0.15); `.bouncy` = (0.5, 0.3). Each named one is identical to its explicit form in the samples.
- **`interpolatingSpring(stiffness:damping:)`** is not integrated: it is the closed-form damped oscillator (exact to 5e-8 at every cadence).
- **Limit:** at the 0.25 ms cadence, 2 samples land one step apart at exact boundaries (max 1.6e-2, early in the curve). That is far below any real frame interval (≥ 4 ms), so it does not matter for the runtime.

The runtime can replace `SpringModel.table` with this integrator for every spring. The table is the default case of it, and the closed-form ω fit (worst 0.01) used for interrupted springs becomes unnecessary: the integrator carries velocity.

## Open: removal (when `animate` returns nil and the value snaps)

Removal times for a 0 → 1 Double (1 ms cadence): default 0.820 s, duration 0.35 → 0.630, bounce 0.3 (= `.bouncy`) → 0.760, bounce −0.3 → 1.227, response 0.4 / 0.7 → 0.614, response 0.55 / 0.825 → 0.577, `.snappy` → 0.557, `interpolatingSpring(170, 15)` → 0.993.

No simple rule fits all seven integrated springs:
- a threshold on remaining distance and velocity (grid search; best total error 455 ms);
- an energy or envelope bound;
- the closed-form state;
- `Spring.settlingDuration(epsilon:)` at any epsilon.

The remaining distance at removal ranges from 2.8e-4 (critically damped) to 5.9e-3 (response 0.55, overshooting). C11 already showed that removal depends on amplitude and display scale for the default spring.

**For R3:**
1. Measure removal across amplitude, display scale and spring parameters with this sampler. It has no screen dependence, and the screen-capture path is only needed for C11's pixel tolerance.
2. Until removal is modelled, keep `SpringModel.settle` (C11) for the default spring.
3. Have the R3 clock cases sample before the earliest removal and again after both sides have settled, as `default-spring-v1` already does. Name this in the R3 decision.
