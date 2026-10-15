#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tv_Tally: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("Tally") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_view_id: View {
    @State private var gen = 0
    @State private var other = 0
    var body: some View {
        VStack(spacing: 0) {
            Witness_tv_Tally().id(gen)
            Button("New id") { gen += 1 }.frame(width: 240, height: 32)
            Button("Same id") { other += 1 }.frame(width: 240, height: 32)
            Text("gen=\(gen) other=\(other)").frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
