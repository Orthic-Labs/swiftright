#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P02: View {
    var body: some View {
        Path { p in
            p.addArc(center: CGPoint(x: 30, y: 30), radius: 20, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false)
        }
        .stroke(Color.green, lineWidth: 3)
        .frame(width: 60, height: 60)
    }
}
