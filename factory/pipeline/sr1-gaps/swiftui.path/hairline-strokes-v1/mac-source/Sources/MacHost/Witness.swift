#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)

private func hline(y: CGFloat, color: Color, width: CGFloat) -> some View {
    Path { p in p.move(to: CGPoint(x: 5, y: y)); p.addLine(to: CGPoint(x: 55, y: y)) }.stroke(color, lineWidth: width)
}

// Issue #63, case hairline-strokes-v1: Rectangle, Circle and Path strokes at lineWidth 0.5, 1 and 1.25 (below the 1.5 px untested threshold at scale 2.5 these are 1.25, 2.5 and 3.1 px).
struct Witness_g63_hairline_strokes_v1: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle().stroke(blue, lineWidth: 0.5).frame(width: 40, height: 24)
                Rectangle().stroke(blue, lineWidth: 1).frame(width: 40, height: 24)
                Rectangle().stroke(blue, lineWidth: 1.25).frame(width: 40, height: 24)
            }
            HStack(spacing: 12) {
                Circle().stroke(orange, lineWidth: 0.5).frame(width: 30, height: 30)
                Circle().stroke(orange, lineWidth: 1).frame(width: 30, height: 30)
                Circle().stroke(orange, lineWidth: 1.25).frame(width: 30, height: 30)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    hline(y: 4, color: green, width: 0.5)
                    hline(y: 14, color: green, width: 1)
                    hline(y: 24, color: green, width: 1.25)
                }.frame(width: 60, height: 30)
            }
        }.frame(width: 240, height: 200)
    }
}
