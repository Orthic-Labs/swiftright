#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P01: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 40))
            p.addLine(to: CGPoint(x: 30, y: 10))
            p.addLine(to: CGPoint(x: 60, y: 30))
            p.closeSubpath()
        }
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 80, height: 50)
    }
}
