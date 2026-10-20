#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


private func zigzag(x0: CGFloat, dx: CGFloat) -> Path {
    Path { p in
        p.move(to: CGPoint(x: x0, y: 52)); p.addLine(to: CGPoint(x: x0 + dx, y: 8)); p.addLine(to: CGPoint(x: x0 + 2 * dx, y: 52))
    }
}

struct Witness_fp_path_joins: View {
    var body: some View {
        ZStack {
            zigzag(x0: 5, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10))
            zigzag(x0: 45, dx: 4).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10))
            zigzag(x0: 85, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            zigzag(x0: 125, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .bevel))
        }.frame(width: 160, height: 60)
    }
}
