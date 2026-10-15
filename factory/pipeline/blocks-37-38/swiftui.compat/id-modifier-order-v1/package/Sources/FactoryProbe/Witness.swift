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

struct Witness_co_id: View {
    @State private var showRed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Toggle") { showRed.toggle() }.frame(width: 100, height: 28)
            // id AFTER onAppear: a new id is a new view, so its onAppear runs again (counts 1, 2, 3)
            HStack(spacing: 8) {
                Color(red: showRed ? 1 : 0, green: 0, blue: showRed ? 0 : 1).frame(width: 40, height: 20).onAppear { cp.a += 1 }.id(showRed)
                CountStrip(n: cp.a, color: Color.green)
            }
            // id BEFORE onAppear: the onAppear belongs to the outer view, which keeps its identity (count stays 1)
            HStack(spacing: 8) {
                Color(red: showRed ? 1 : 0, green: 0, blue: showRed ? 0 : 1).frame(width: 40, height: 20).id(showRed).onAppear { cp.b += 1 }
                CountStrip(n: cp.b, color: Color.orange)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
