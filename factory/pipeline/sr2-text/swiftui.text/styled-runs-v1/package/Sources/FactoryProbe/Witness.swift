#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

// Issue #68 styled Text runs, case styled-runs-v1 (default body font, so the system font is the Segoe UI / SF pair of decision 2).
// Row 1: Text + Text, one line with three runs (plain, bold, blue). Row 2: Text(AttributedString) with a yellow-background run and an underlined run.
struct Witness_r68_styled_runs_v1_inner: View {
    private var attributed: AttributedString {
        var lead = AttributedString("marked ")
        lead.backgroundColor = Color.yellow
        var tail = AttributedString("underlined")
        tail.underlineStyle = Text.LineStyle.single
        return lead + tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plain ") + Text("bold").bold() + Text(" link").foregroundColor(.blue)
            Text(attributed)
        }
    }
}

struct Witness_r68_styled_runs_v1: View {
    var body: some View { Witness_r68_styled_runs_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
