#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


private func curves() -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 10, y: 60))
    p.addQuadCurve(to: CGPoint(x: 40, y: 60), control: CGPoint(x: 25, y: 20))
    p.addCurve(to: CGPoint(x: 70, y: 60), control1: CGPoint(x: 50, y: 95), control2: CGPoint(x: 60, y: 95))
    p.addArc(center: CGPoint(x: 80, y: 30), radius: 12, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
    p.addEllipse(in: CGRect(x: 10, y: 10, width: 30, height: 18))
    p.addPath(Path(ellipseIn: CGRect(x: 0, y: 0, width: 16, height: 10)).applying(CGAffineTransform(scaleX: 1.5, y: 1.5)).offsetBy(dx: 55, dy: 70))
    return p
}

struct Witness_fp_path_curves: View {
    var body: some View {
        curves().stroke(blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).frame(width: 100, height: 100)
    }
}
