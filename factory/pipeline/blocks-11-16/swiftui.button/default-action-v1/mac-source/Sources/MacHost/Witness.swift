#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_default_action: View {
    var body: some View {
        Button("Run") {}.keyboardShortcut(.defaultAction).frame(width: 100, height: 40)
    }
}
