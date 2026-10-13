#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_plain_disabled: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.plain).disabled(true).frame(width: 100, height: 40)
    }
}
