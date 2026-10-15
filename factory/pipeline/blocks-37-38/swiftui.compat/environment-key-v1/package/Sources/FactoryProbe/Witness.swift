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

private struct CustomValueKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var customValue: Int { get { self[CustomValueKey.self] } set { self[CustomValueKey.self] = newValue } }
}

struct Witness_co_envsub: View {
    @Environment(\.customValue) private var value
    var body: some View { Rectangle().fill(Color.red).frame(width: CGFloat(value) * 20 + 10, height: 14) }
}

struct Witness_co_env: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Witness_co_envsub()                                        // the default (0): 10 pt wide
            Witness_co_envsub().environment(\.customValue, 1)           // upstream: the subview reads 1 (30 pt)
            Witness_co_envsub().environment(\.customValue, 2).environment(\.customValue, 3)   // the nearest write wins: 2 (50 pt)
            VStack(spacing: 4) { Witness_co_envsub(); Witness_co_envsub().environment(\.customValue, 4) }.environment(\.customValue, 1)   // 30 pt and 90 pt
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
