#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)

// Issue #63, case mixed-layout-v1: the small mixed layout (text, filled rect, rounded-rect stroke, circle) to be rerun at render scale 1.25 and 1.5.
// factory/tools/pair.py has ONE capture scale (CAPTURE_SCALE 2.5), so this case runs at 2.5; the scale variants need a per-case scale (see the lead's report).
struct Witness_g63_mixed_layout_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mixed layout")
            Rectangle().fill(blue).frame(width: 90, height: 24)
            RoundedRectangle(cornerRadius: 8, style: .circular).stroke(red, lineWidth: 2).frame(width: 90, height: 34)
            Circle().fill(red).frame(width: 30, height: 30)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
