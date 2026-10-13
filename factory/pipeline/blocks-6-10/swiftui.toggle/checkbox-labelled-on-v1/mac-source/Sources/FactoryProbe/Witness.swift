#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_toggle_checkbox_labelled_on: View {
    @State private var enabled = true
    var body: some View {
        Toggle("Enabled", isOn: $enabled).toggleStyle(.automatic)
    }
}
