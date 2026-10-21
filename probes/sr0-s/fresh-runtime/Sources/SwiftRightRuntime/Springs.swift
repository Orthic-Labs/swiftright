import Foundation

// SR2 block R3 (issue #38, docs/sr2-plan.md): SwiftUI's parameterised springs.
//
// Measured on macOS 27.0.1 (26A434) in the R3 spike (factory/pipeline/sr2-r3-spike/SPIKE-RESULT.md): every built-in spring steps a unit-mass spring
// with semi-implicit Euler at a fixed 1/300 s and holds the value between steps; a call at time t has taken every step that ends strictly before t.
// Reproduced to 5e-8 at 1, 12.5 and 100 ms cadences. `interpolatingSpring` is the closed-form damped oscillator instead.
//   spring(duration: d, bounce: b):            omega = 2 pi / d, zeta = 1 - b (b >= 0) or 1 / (1 + b) (b < 0); k = omega^2, c = 2 zeta omega
//   spring(response: r, dampingFraction: f):   omega = 2 pi / r, zeta = f
//   .snappy / .bouncy:                         duration 0.5, bounce 0.15 / 0.3 (each `extraBounce` adds to the bounce)
// `.default`, `.smooth` and `.spring` keep the measured table (`SpringModel`, decision C4), which is this integrator sampled at 12.5 ms.
// Removal (#54, docs/sr2-plan.md): the spike found no parameterised-spring rule of its own, so every spring (table, integrated, closed form, and a spring that
// continues from an interrupted one) is removed by SwiftUI's documented settling rule (`Spring.settlingDuration`: the time after which ALL later values stay
// within epsilon) applied per component with the measured C11 tolerances (`SpringModel.tolerances`: x, y 0.5 / scale pt; width, height 1.05 / scale pt;
// opacity-like values, which colour and scale changes count as, 0.0006; a stroke's line width as a width). `integratedSettle`, `closedSettle`,
// `SpringModel.settle` and `MotionLayer.motionDuration` are that one rule over each form.
// Not modelled: `blendDuration`, and a non-zero `initialVelocity` (the notch uses neither).

extension Animation {
    /// Apple: https://developer.apple.com/documentation/swiftui/animation/spring(duration:bounce:blendduration:)
    public static func spring(duration: Double = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
        if duration == 0.5 && bounce == 0 { return Animation(name: "spring", duration: 0.5, curve: .spring) }
        return Animation(name: "spring", duration: duration, curve: SpringParameters(duration: duration, bounce: bounce).curve)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:)
    /// Disfavoured so `.spring()` is the duration/bounce form, as in SwiftUI (macOS 27: `.spring() == .spring(duration: 0.5, bounce: 0)`).
    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        // SwiftUI: the default spring is `response 0.5, dampingFraction 1` (it prints as FluidSpringAnimation(response: 0.5, dampingFraction: 1.0)).
        if response == 0.5 && dampingFraction == 1 { return Animation(name: "spring", duration: 0.5, curve: .spring) }
        let omega = 2 * Double.pi / max(response, 1e-6)
        return Animation(name: "spring", duration: response, curve: .integratedSpring(stiffness: omega * omega, damping: 2 * dampingFraction * omega))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/animation/smooth(duration:extrabounce:)
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        if duration == 0.5 && extraBounce == 0 { return .smooth }
        return Animation(name: "smooth", duration: duration, curve: SpringParameters(duration: duration, bounce: extraBounce).curve)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/animation/snappy
    public static var snappy: Animation { snappy() }
    /// Apple: https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        Animation(name: "snappy", duration: duration, curve: SpringParameters(duration: duration, bounce: 0.15 + extraBounce).curve)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/animation/bouncy
    public static var bouncy: Animation { bouncy() }
    /// Apple: https://developer.apple.com/documentation/swiftui/animation/bouncy(duration:extrabounce:)
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        Animation(name: "bouncy", duration: duration, curve: SpringParameters(duration: duration, bounce: 0.3 + extraBounce).curve)
    }

    /// The closed-form damped oscillator (not integrated). `initialVelocity` other than 0 is not modelled.
    /// Apple: https://developer.apple.com/documentation/swiftui/animation/interpolatingspring(mass:stiffness:damping:initialvelocity:)
    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Animation {
        let m = max(mass, 1e-6)
        let k = stiffness / m, c = damping / m
        return Animation(name: "interpolatingSpring", duration: SpringMath.closedSettle(k: k, c: c, displacement: 1, tolerance: 0.001),
                         curve: .closedSpring(stiffness: k, damping: c))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/animation/interpolatingspring(duration:bounce:initialvelocity:)
    public static func interpolatingSpring(duration: Double = 0.5, bounce: Double = 0, initialVelocity: Double = 0) -> Animation {
        guard case .integratedSpring(let k, let c) = SpringParameters(duration: duration, bounce: bounce).curve else { return .default }
        return Animation(name: "interpolatingSpring", duration: duration, curve: .closedSpring(stiffness: k, damping: c))
    }

    /// This animation starting `delay` seconds after its layer begins. Apple: https://developer.apple.com/documentation/swiftui/animation/delay(_:)
    public func delay(_ delay: Double) -> Animation {
        var copy = self
        copy.delay = self.delay + max(0, delay)
        return copy
    }
}

/// `spring(duration:bounce:)` as stiffness and damping for unit mass.
struct SpringParameters {
    let duration: Double
    let bounce: Double

    var curve: Animation.Curve {
        let omega = 2 * Double.pi / max(duration, 1e-6)
        let b = min(max(bounce, -0.99), 1)
        let zeta = b >= 0 ? 1 - b : 1 / (1 + b)
        return .integratedSpring(stiffness: omega * omega, damping: 2 * zeta * omega)
    }
}

/// The integrator and closed forms behind the parameterised springs.
@MainActor
enum SpringMath {
    static let step = 1.0 / 300

    /// A parameterised spring that interrupts a spring starts with this multiple of the presented velocity. MEASURED (CI 39595832450, macOS 27, spring-removal-v1, `.bouncy` 100 -> 250 pt
    /// interrupted at 0.205 s by `.bouncy` back to 100, 20 clock samples): the motion after the interruption is ONE semi-implicit Euler integration of the new spring from the
    /// presented position, with 2.34 x the velocity the old spring had, and the same 1/300 s steps. Fitted: 0.1 pt of the Mac's bar edge at every sample but one (0.5 pt at 0.5 s),
    /// where a closed-form continuation at the same velocity is up to 15 pt off and the old rule (1 x) 13 pt. One scenario only: the factor is not yet known to depend on the spring.
    static let mergedVelocityFactor = 2.34

    /// Steps an integrated spring that continued from an interrupted one has taken `elapsed` seconds after the interruption. Fitted to the 20 Mac samples (CI 39595832450): the step
    /// ends fall on `interruption + (n + 3/4) h` for n >= -1 (any phase from 0.6 to 1 h fits every sample), a step counts when it ends strictly before the sample, so
    /// `ceil(elapsed / h - 3/4) + 1`: 10 steps at 0.03 s, 89 at 0.295 s after (88.5 h). Zero at the interruption itself, where the old value is still
    /// shown (Mac, 0.205 s: the old spring's own value to 1e-3 pt).
    static func continuedSteps(elapsed: Double) -> Int {
        guard elapsed > 0 else { return 0 }
        return max(1, Int((elapsed / step - 0.75 - 1e-9).rounded(.up)) + 1)
    }

    /// Displacement from the target `elapsed` seconds after an interruption, starting from displacement `d0` with rate `v0` (already scaled by `mergedVelocityFactor`):
    /// semi-implicit Euler, `v += (-k d - c v) h; d += v h`, the integrator every built-in spring uses.
    static func continuedDisplacement(d0: Double, v0: Double, k: Double, c: Double, elapsed: Double) -> Double {
        var d = d0, v = v0
        for _ in 0..<min(continuedSteps(elapsed: elapsed), 3 * 300 * 10) {
            v += (-k * d - c * v) * step
            d += v * step
        }
        return d
    }

    private struct Key: Hashable { let k: Double; let c: Double }
    /// Per spring: `ends[n]` is the time step n+1 ends (accumulated as SwiftUI does), `values[n]` the value after n+1 steps, from rest at 0 toward 1.
    private static var trajectories: [Key: (ends: [Double], values: [Double])] = [:]

    private static func trajectory(k: Double, c: Double, through t: Double) -> (ends: [Double], values: [Double]) {
        let key = Key(k: k, c: c)
        // Springs whose parameters vary continuously (driven by a slider, say) would grow the cache without bound: start over past 64 springs.
        if trajectories[key] == nil && trajectories.count >= 64 {
            trajectories.removeAll()
            velocities.removeAll()
        }
        var tr = trajectories[key] ?? (ends: [], values: [])
        if (tr.ends.last ?? 0) < t {
            var x = tr.values.last ?? 0
            var v = tr.ends.isEmpty ? 0 : velocities[key] ?? 0
            var acc = tr.ends.last ?? 0
            while acc < t + step {
                v += (k * (1 - x) - c * v) * step
                x += v * step
                acc += step
                tr.ends.append(acc)
                tr.values.append(x)
            }
            velocities[key] = v
            trajectories[key] = tr
        }
        return tr
    }
    private static var velocities: [Key: Double] = [:]

    /// Progress (0 at rest, 1 at the target; may overshoot) of an integrated spring `elapsed` seconds after it started from rest.
    static func integrated(k: Double, c: Double, elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let tr = trajectory(k: k, c: c, through: elapsed)
        // steps taken = number of step ends strictly before `elapsed`
        var lo = 0, hi = tr.ends.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tr.ends[mid] < elapsed { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? 0 : tr.values[lo - 1]
    }

    /// Rate of change of progress (1/s) of an integrated spring from rest `elapsed` seconds in: the velocity after the steps taken, which is the
    /// last step's change over the step (semi-implicit Euler: x_n - x_(n-1) = v_n h). Exact at any tick alignment.
    static func integratedRate(k: Double, c: Double, elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let tr = trajectory(k: k, c: c, through: elapsed)
        var lo = 0, hi = tr.ends.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tr.ends[mid] < elapsed { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return 0 }
        return (tr.values[lo - 1] - (lo >= 2 ? tr.values[lo - 2] : 0)) / step
    }

    /// Seconds after which an integrated spring from rest is removed: every component's remainder (|1 - progress| x its displacement) stays within
    /// its C11 tolerance from then on (x, y 0.5 / scale pt; width, height 1.05 / scale pt; opacity 0.0006). Capped at 10 s.
    static func integratedSettle(k: Double, c: Double, displacement: [Double], scale: Double) -> Double {
        let tolerance = SpringModel.tolerances(scale: scale)
        let horizon = 10.0
        let tr = trajectory(k: k, c: c, through: horizon)
        var last = -1
        for n in tr.values.indices {
            let remaining = abs(1 - tr.values[n])
            for i in 0..<min(displacement.count, tolerance.count) where remaining * abs(displacement[i]) > tolerance[i] { last = n; break }
        }
        if last < 0 { return 0 }
        return last + 1 < tr.ends.count ? tr.ends[last + 1] : horizon
    }

    /// The free motion of a displacement `d0` with rate `v0` under stiffness `k` and damping `c` (unit mass), `t` seconds later.
    nonisolated static func free(d0: Double, v0: Double, k: Double, c: Double, t: Double) -> Double {
        let disc = c * c - 4 * k
        if abs(disc) < 1e-9 {
            let w = c / 2
            return (d0 + (v0 + w * d0) * t) * exp(-w * t)
        }
        if disc > 0 {
            let s = disc.squareRoot()
            let r1 = (-c + s) / 2, r2 = (-c - s) / 2
            let a = (v0 - r2 * d0) / (r1 - r2), b = d0 - a
            return a * exp(r1 * t) + b * exp(r2 * t)
        }
        let wd = (-disc).squareRoot() / 2, decay = c / 2
        return exp(-decay * t) * (d0 * cos(wd * t) + (v0 + decay * d0) / wd * sin(wd * t))
    }

    /// Progress of the closed-form spring from rest.
    nonisolated static func closed(k: Double, c: Double, elapsed: Double) -> Double {
        elapsed <= 0 ? 0 : 1 - free(d0: 1, v0: 0, k: k, c: c, t: elapsed)
    }

    /// Seconds after which a closed-form spring of `displacement` stays within `tolerance` (1 ms grid, capped at 10 s).
    nonisolated static func closedSettle(k: Double, c: Double, displacement: Double, tolerance: Double) -> Double {
        var last = 0.0
        var t = 0.0
        while t < 10 {
            if abs(free(d0: 1, v0: 0, k: k, c: c, t: t)) * abs(displacement) > tolerance { last = t + 0.001 }
            t += 0.001
        }
        return last
    }
}
