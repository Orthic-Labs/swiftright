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

@Observable final class CounterModel { var a = 0 }

struct Witness_obs_property: View {
    @State private var model = CounterModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<model.a, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10)
            Text("a=\(model.a)").frame(width: 240, height: 20)
            Button("Add") { model.a += 1 }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
