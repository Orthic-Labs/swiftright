#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_bordered: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.bordered).frame(width: 100, height: 40)
    }
}
