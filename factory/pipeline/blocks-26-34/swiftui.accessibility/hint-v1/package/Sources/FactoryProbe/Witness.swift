#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ax_hint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Run") { }.accessibilityHint("Starts the scan").frame(width: 240, height: 32)
            Text("Label only").accessibilityLabel("Custom name").accessibilityHint("A hint").frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
