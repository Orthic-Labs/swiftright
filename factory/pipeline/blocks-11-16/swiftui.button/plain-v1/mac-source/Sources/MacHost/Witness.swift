#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_plain: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.plain).frame(width: 100, height: 40)
    }
}
