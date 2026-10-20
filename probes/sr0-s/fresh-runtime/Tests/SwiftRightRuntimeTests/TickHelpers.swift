import Foundation
@testable import SwiftRightRuntime

extension Graph {
    /// Ticks from `from` to `to` in steps of at most 0.5 s (a display host never leaves a gap over 1 s, past which SwiftUI clamps a spring: SR2 R3).
    @MainActor func tickSteps(from: Double, to: Double) {
        var t = from
        while t < to { t = min(t + 0.5, to); tick(now: t) }
    }
}
