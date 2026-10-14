#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

enum Feed {
    static let pair = AsyncStream<Int>.makeStream()
    nonisolated(unsafe) static var script = [3, 1, 2]
    nonisolated(unsafe) static var sent = 0
    static func send() { Feed.pair.continuation.yield(script[sent % script.count]); sent += 1 }
    static func burst() { send(); send(); send() }
    static func finish() { Feed.pair.continuation.finish() }
}

func swatch(_ v: Int) -> Color {
    switch v % 4 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    default: return Color.gray
    }
}

struct Listener: View {
    @Binding var value: Int
    @Binding var phase: String
    var body: some View {
        Rectangle().fill(Color.gray).frame(width: 240, height: 20)
            .task { for await v in Feed.pair.stream { value = v }; phase = "ended" }
    }
}

struct Witness_task_cancel: View {
    @State private var value = 0
    @State private var phase = "listening"
    @State private var shown = true
    var body: some View {
        VStack(spacing: 0) {
            if shown { Listener(value: $value, phase: $phase) } else { Rectangle().fill(Color.black).frame(width: 240, height: 20) }
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("value=\(value) phase=\(phase) shown=\(shown ? 1 : 0)").frame(width: 240, height: 20)
            Button("Next") { Feed.send() }.frame(width: 240, height: 40)
            Button("Hide") { shown = false }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
