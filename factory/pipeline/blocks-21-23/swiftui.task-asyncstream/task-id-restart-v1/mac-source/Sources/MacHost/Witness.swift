#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

enum Feeds {
    nonisolated(unsafe) static var streams: [Int: AsyncStream<Int>] = [:]
    nonisolated(unsafe) static var conts: [Int: AsyncStream<Int>.Continuation] = [:]
    nonisolated(unsafe) static var sent = 0
    static func stream(_ gen: Int) -> AsyncStream<Int> {
        if let s = streams[gen] { return s }
        let p = AsyncStream<Int>.makeStream()
        streams[gen] = p.stream; conts[gen] = p.continuation
        return p.stream
    }
    static func send(_ gen: Int) { _ = stream(gen); sent += 1; conts[gen]?.yield(sent) }
}

func swatch(_ v: Int) -> Color {
    switch v % 4 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    default: return Color.gray
    }
}

struct Witness_task_restart: View {
    @State private var gen = 0
    @State private var value = 0
    @State private var started = "0"
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("gen=\(gen) value=\(value) started=\(started)").frame(width: 240, height: 20)
            Button("Send") { Feeds.send(gen) }.frame(width: 240, height: 40)
            Button("Restart") { gen += 1 }.frame(width: 240, height: 40)
            Button("Old") { Feeds.send(gen - 1) }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
        .task(id: gen) { if gen > 0 { started += "," + String(gen) }; for await v in Feeds.stream(gen) { value = v } }
    }
}
