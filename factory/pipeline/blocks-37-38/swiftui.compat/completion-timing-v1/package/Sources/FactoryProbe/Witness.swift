#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

#if !os(Windows)
import Observation
#endif

@Observable final class CompatProbe {
    var a = 0
    var b = 0
    var tasks = 0
    var values: [Int] = []
    var changes: [[Int]] = []
}
nonisolated(unsafe) let cp = CompatProbe()

struct CountStrip: View {
    let n: Int
    let color: Color
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<8, id: \.self) { i in Rectangle().fill(i < n ? color : Color(white: 0.88)).frame(width: 8, height: 8) } }
    }
}

@Observable final class CtimeProbe {
    var markInner = -1
    var markOuter = -1
    var t0 = Date()
    func late() -> Int { Date().timeIntervalSince(t0) > 0.15 ? 1 : 0 }
}
nonisolated(unsafe) let ctp = CtimeProbe()

struct CtimeMark: View {
    let mark: Int
    var body: some View { Rectangle().fill(mark < 0 ? Color.gray : (mark == 1 ? Color.green : Color.red)).frame(width: mark == 1 ? 40 : 8, height: 6) }
}

struct Witness_co_ctime: View {
    @State private var x = 0
    @State private var y = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Run") {
                ctp.t0 = Date()
                withAnimation(.linear(duration: 1)) {
                    withAnimation(nil) { x = 1 } completion: { y = 2; ctp.markInner = ctp.late() }
                } completion: { ctp.markOuter = ctp.late() }
            }.frame(width: 100, height: 28)
            // x (orange) is written under the inner withAnimation(nil) and snaps. y (blue) is written by the inner completion: if SwiftUI runs that completion
            // after the outer transaction closes (asynchronously), y does not take the outer 1 s linear animation and is 50 pt at the mid sample; if it ran
            // inside the open outer transaction, y animates (about 26 pt at 0.4 s). The marks record when each completion ran (green = after 0.15 s, red = at once,
            // gray = never). Nothing here is asserted from SwiftUI documentation: the Mac capture is the reference.
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(x) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(y) * 20 + 10, height: 6)
            }
            HStack(spacing: 4) { CtimeMark(mark: ctp.markInner); CtimeMark(mark: ctp.markOuter) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
