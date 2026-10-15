#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tv_state_initial_inner: View {
    @State private var n: Int
    init(start: Int) { _n = State(initialValue: start) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Text("n=\(n)").frame(width: 240, height: 20, alignment: .leading)
            Button("Add") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_state_initial: View {
    var body: some View { Witness_tv_state_initial_inner(start: 3).frame(width: 240, height: 200, alignment: .top) }
}
