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

@Observable final class Settings { var on = false; var count = 0 }

struct Editor: View {
    @Bindable var s: Settings
    var body: some View {
        let on = $s.on
        Button("Flip") { Box.stamp += 1; on.wrappedValue.toggle() }.frame(width: 240, height: 32)
    }
}

struct OnReader: View {
    let s: Settings
    var body: some View { HStack(spacing: 0) { Rectangle().fill(s.on ? Color.green : Color.red).frame(width: 40, height: 20); Text("on=\(s.on ? 1 : 0) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading) }.frame(width: 240, height: 20) }
}

struct CountReader: View {
    let s: Settings
    var body: some View { HStack(spacing: 0) { Rectangle().fill(swatch(Box.stamp)).frame(width: 40, height: 20); Text("count=\(s.count) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading) }.frame(width: 240, height: 20) }
}

struct Witness_obs_bindable: View {
    @State private var s = Settings()
    var body: some View {
        VStack(spacing: 0) {
            Editor(s: s)
            OnReader(s: s)
            CountReader(s: s)
            Button("Count+") { Box.stamp += 1; s.count += 1 }.frame(width: 240, height: 32)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
