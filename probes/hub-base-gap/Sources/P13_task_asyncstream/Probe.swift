#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P13: View {
    @State private var n = 0
    var body: some View {
        Text("\(n)")
            .task {
                let s = AsyncStream<Int> { c in c.yield(1); c.yield(2); c.finish() }
                for await v in s { n = v }
            }
    }
}
