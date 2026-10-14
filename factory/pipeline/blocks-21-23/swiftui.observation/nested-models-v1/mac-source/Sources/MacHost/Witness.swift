#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

enum Box { nonisolated(unsafe) static var stamp = 0 }

func swatch(_ s: Int) -> Color {
    switch s % 6 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    case 4: return Color.orange
    case 5: return Color.purple
    default: return Color.gray
    }
}

@Observable final class Inner { var v = 0; init(_ v: Int = 0) { self.v = v } }
@Observable final class Outer { var inner = Inner(); var other = 0 }

struct InnerReader: View {
    let o: Outer
    var body: some View { HStack(spacing: 0) { Rectangle().fill(swatch(Box.stamp)).frame(width: 40, height: 20); Text("inner=\(o.inner.v) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading) }.frame(width: 240, height: 20) }
}

struct Witness_obs_nested: View {
    @State private var o = Outer()
    @State private var retired: Inner? = nil
    var body: some View {
        VStack(spacing: 0) {
            InnerReader(o: o)
            Button("Inner+") { Box.stamp += 1; o.inner.v += 1 }.frame(width: 240, height: 32)
            Button("Other+") { Box.stamp += 1; o.other += 1 }.frame(width: 240, height: 32)
            Button("Swap") { Box.stamp += 1; retired = o.inner; o.inner = Inner(100) }.frame(width: 240, height: 32)
            Button("Old+") { Box.stamp += 1; retired?.v += 1 }.frame(width: 240, height: 32)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
