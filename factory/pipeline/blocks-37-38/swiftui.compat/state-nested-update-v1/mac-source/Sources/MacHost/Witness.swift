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

struct Witness_co_state: View {
    @State private var value = 0
    var body: some View {
        let _ = cp.values.append(value)
        VStack(alignment: .leading, spacing: 8) {
            Color.white.frame(width: 20, height: 10)
                .onAppear {
                    value = 1
                    value = 2
                    withAnimation { value = 3; value = 4 }
                }
                .onChange(of: value) { oldValue, newValue in cp.changes.append([oldValue, newValue]) }
            // the values the body saw, one bar per evaluation (width 12 pt x value + 4): upstream expects [0, 2, 4]
            HStack(spacing: 2) { ForEach(0..<cp.values.count, id: \.self) { i in Rectangle().fill(Color.green).frame(width: CGFloat(cp.values[i]) * 12 + 4, height: 10) } }
            // the onChange pairs, a bar for the old value above a bar for the new: upstream expects [[0, 2], [2, 4]]
            HStack(spacing: 6) { ForEach(0..<cp.changes.count, id: \.self) { i in VStack(spacing: 2) { Rectangle().fill(Color.orange).frame(width: CGFloat(cp.changes[i][0]) * 12 + 4, height: 8); Rectangle().fill(Color.purple).frame(width: CGFloat(cp.changes[i][1]) * 12 + 4, height: 8) } } }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
