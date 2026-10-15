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

struct Witness_co_task: View {
    @State private var value = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Bump") { value += 1 }.frame(width: 100, height: 28)
            HStack(spacing: 8) {
                Color.red.frame(width: 40, height: 20).task(id: value) { cp.tasks += 1 }
                CountStrip(n: cp.tasks, color: Color.blue)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
