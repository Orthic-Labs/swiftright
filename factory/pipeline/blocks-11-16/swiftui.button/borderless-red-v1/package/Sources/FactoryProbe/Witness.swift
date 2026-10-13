#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_borderless_red: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.borderless).foregroundStyle(Color.red).frame(width: 100, height: 40)
    }
}
