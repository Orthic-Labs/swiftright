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

struct Witness_task_order_burst: View {
    @State private var log: [Int] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<log.count, id: \.self) { i in Rectangle().fill(swatch(log[i])).frame(width: 40, height: 20) } }.frame(width: 240, height: 20, alignment: .leading)
            Text("log=\(log.map { String($0) }.joined(separator: ","))").frame(width: 240, height: 20)
            Button("Burst") { Feed.burst() }.frame(width: 240, height: 40)
            Button("Next") { Feed.send() }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
        .task { for await v in Feed.pair.stream { log.append(v) } }
    }
}
