#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


private func pentagram() -> Path {
    Path { p in
        func vertex(_ k: Int) -> CGPoint {
            let a = -Double.pi / 2 + Double(k) * 2 * Double.pi / 5
            return CGPoint(x: 30 + 26 * cos(a), y: 30 + 26 * sin(a))
        }
        p.move(to: vertex(0)); p.addLine(to: vertex(2)); p.addLine(to: vertex(4)); p.addLine(to: vertex(1)); p.addLine(to: vertex(3))
        p.closeSubpath()
    }
}

struct Witness_fp_path_fill_nonzero: View {
    var body: some View {
        pentagram().fill(orange).frame(width: 60, height: 60)
    }
}
