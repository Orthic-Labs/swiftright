// SR0 negative fixture: `Timer.publish` (Combine) is outside the SR0 slice (CONTRACT §2).
// Expected: FAIL with "type 'Timer' has no member 'publish'".
import Foundation
import SwiftRightRuntime

struct TimerPublishScreen: View {
    let ticks = Timer.publish(every: 1, on: .main, in: .common)
    var body: some View {
        Text("tick")
    }
}
