#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_borderless_disabled: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.borderless).disabled(true).frame(width: 100, height: 40)
    }
}
