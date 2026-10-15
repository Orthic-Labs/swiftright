#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tv_CounterA: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("A+") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_CounterB: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.blue).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("B+") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_anyview: View {
    @State private var useB = false
    @State private var bump = 0
    var body: some View {
        let shown: AnyView = useB ? AnyView(Witness_tv_CounterB()) : AnyView(Witness_tv_CounterA())
        return VStack(spacing: 0) {
            shown
            Button("Swap") { useB.toggle() }.frame(width: 240, height: 32)
            Button("Bump") { bump += 1 }.frame(width: 240, height: 32)
            Text("bump=\(bump)").frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
