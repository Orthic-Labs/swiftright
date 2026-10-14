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

@Observable final class Sum { var a = 0; var b = 0; var total: Int { a + b } }

struct TotalReader: View {
    let m: Sum
    var body: some View { HStack(spacing: 0) { Rectangle().fill(swatch(Box.stamp)).frame(width: 40, height: 20); Text("total=\(m.total) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading) }.frame(width: 240, height: 20) }
}

struct AReader: View {
    let m: Sum
    var body: some View { HStack(spacing: 0) { Rectangle().fill(swatch(Box.stamp)).frame(width: 40, height: 20); Text("a=\(m.a) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading) }.frame(width: 240, height: 20) }
}

struct Witness_obs_computed: View {
    @State private var m = Sum()
    var body: some View {
        VStack(spacing: 0) {
            TotalReader(m: m)
            AReader(m: m)
            Button("B+") { Box.stamp += 1; m.b += 1 }.frame(width: 240, height: 32)
            Button("A+") { Box.stamp += 1; m.a += 1 }.frame(width: 240, height: 32)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
