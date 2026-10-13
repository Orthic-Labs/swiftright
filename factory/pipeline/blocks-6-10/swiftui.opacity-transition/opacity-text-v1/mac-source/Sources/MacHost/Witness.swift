#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case opacity-text: `.opacity(0.5)` on Text (alpha baked into the text run's colour). Glyph pixels differ by decision 2 (Segoe UI vs SF);
// the ink colour is gated (pair_textcolour_report.py) and everything outside the glyph regions must match exactly.
struct Witness_opacity_text: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Red").foregroundStyle(Color.red).opacity(0.5)
            Text("Plain").opacity(0.5)
            Text("Full")
        }
        .frame(width: 160, height: 120)
    }
}
