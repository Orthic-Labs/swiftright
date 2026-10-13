#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_view_label_plain: View {
    var body: some View {
        Button(action: {}) { Rectangle().fill(Color.red).frame(width: 32, height: 12) }.buttonStyle(.plain)
    }
}
