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

struct Witness_task_drives: View {
    @State private var value = 0
    @State private var phase = "idle"
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("value=\(value) phase=\(phase)").frame(width: 240, height: 20)
            Button("Next") { Feed.send() }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
        .task { phase = "running"; for await v in Feed.pair.stream { value = v }; phase = "done" }
    }
}
