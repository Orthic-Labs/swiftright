#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


private func hline(y: CGFloat) -> Path {
    Path { p in p.move(to: CGPoint(x: 5, y: y)); p.addLine(to: CGPoint(x: 55, y: y)) }
}

struct Witness_fp_stroke_hairline: View {
    var body: some View {
        ZStack {
            hline(y: 6).stroke(blue, lineWidth: 0.4)
            hline(y: 15).stroke(blue, lineWidth: 0.5)
            hline(y: 24).stroke(blue, lineWidth: 1)
        }.frame(width: 60, height: 30)
    }
}
