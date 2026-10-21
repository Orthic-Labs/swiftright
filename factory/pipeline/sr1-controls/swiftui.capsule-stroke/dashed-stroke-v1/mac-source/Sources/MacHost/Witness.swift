#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)

// Issue #76, case dashed-stroke-v1: dashed strokes (host bitmap route; the renderer does not draw dashes): a rounded rectangle, a circle and an open line, dash [6, 4], line width 2.
struct Witness_g76_dashed_stroke_v1: View {
    var body: some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 10, style: .circular).stroke(blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).frame(width: 110, height: 70)
            Circle().stroke(blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).frame(width: 70, height: 70)
            Path { p in p.move(to: CGPoint(x: 0, y: 35)); p.addLine(to: CGPoint(x: 70, y: 35)) }
                .stroke(blue, style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [6, 4])).frame(width: 70, height: 70)
        }
    }
}
