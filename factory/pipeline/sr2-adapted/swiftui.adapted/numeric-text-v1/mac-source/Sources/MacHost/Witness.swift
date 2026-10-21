#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #55, case numeric-text-v1: two counters under .contentTransition(.numericText()) change inside withAnimation(.linear(duration: 1)): 9 -> 10 (a digit is added: the 9
// leaves as the 0 arrives and the 1 comes in) and 41 -> 42 (the 4 stays, the 1 rolls to the 2). Frames 0, 0.25, 0.5, 0.75, 1 of the manual clock: frames 1-3 are the roll,
// frame 4 is the settled text. Glyph shapes differ (Segoe UI Variable vs SF), so the glyph bands are excluded and the semantic frames (final text) are gated; what the
// mid frames decide (travel distance, fade curve, clipping to the line box) is read from the first CI pair.
struct Witness_e55_numeric_text_v1: View {
    @State private var a = 9
    @State private var b = 41
    var body: some View {
        VStack(spacing: 10) {
            Text("\(a)").font(.system(size: 28)).monospacedDigit().contentTransition(.numericText())
            Text("\(b)").font(.system(size: 28)).monospacedDigit().contentTransition(.numericText())
        }
        .frame(width: 240, height: 160)
        .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { a = 10; b = 42 } }
    }
}
