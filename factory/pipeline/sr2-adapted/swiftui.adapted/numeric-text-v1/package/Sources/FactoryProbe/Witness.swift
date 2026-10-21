#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #55, case numeric-text-v1: two counters under .contentTransition(.numericText()) change WITHOUT an animation transaction (9 -> 10, 41 -> 42): the text swaps at once,
// layout is that of the new text. Static case: SwiftUI's numericText roll cannot be sampled on the factory clock (CI 39585953303: the Mac host showed the settled text
// already at frame 0 and identical frames after, the roll runs in SwiftUI's render server, not on the manual clock), so the roll is covered by the runtime and painter
// unit tests only (Issue55NumericTextTests, Issue55NumericTextPainterTests). Glyph shapes differ (Segoe UI Variable vs SF): the glyph bands are excluded.
struct Witness_e55_numeric_text_v1: View {
    @State private var a = 9
    @State private var b = 41
    var body: some View {
        VStack(spacing: 10) {
            Text("\(a)").font(.system(size: 28)).monospacedDigit().contentTransition(.numericText())
            Text("\(b)").font(.system(size: 28)).monospacedDigit().contentTransition(.numericText())
        }
        .frame(width: 240, height: 160)
        .onAppear { a = 10; b = 42 }
    }
}
