#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_borderless: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.borderless).frame(width: 100, height: 40)
    }
}
