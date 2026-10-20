#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


struct Witness_fp_dash_phase: View {
    var body: some View {
        Path { p in p.move(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 55, y: 10)) }
            .stroke(blue, style: StrokeStyle(lineWidth: 4, dash: [6, 3], dashPhase: 2)).frame(width: 60, height: 20)
    }
}
