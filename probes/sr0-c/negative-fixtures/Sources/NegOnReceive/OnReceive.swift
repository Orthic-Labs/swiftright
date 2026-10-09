// SR0 negative fixture: `.onReceive` is outside the SR0 slice (CONTRACT §2).
// Expected: FAIL on Windows and Mac with "value of type 'Text' has no member 'onReceive'".
// The argument is a placeholder Int so the only failing name is onReceive itself.
import SwiftRightRuntime

struct OnReceiveScreen: View {
    let source = 0
    var body: some View {
        Text("tick").onReceive(source) { _ in }
    }
}
