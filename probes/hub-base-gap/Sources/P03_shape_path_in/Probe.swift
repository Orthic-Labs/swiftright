#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct Spark: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)), y: rect.height * (1 - CGFloat(v)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
struct P03: View {
    var body: some View {
        Spark(values: [0.1, 0.5, 0.3, 0.9]).stroke(Color.red, lineWidth: 2).frame(width: 80, height: 40)
    }
}
