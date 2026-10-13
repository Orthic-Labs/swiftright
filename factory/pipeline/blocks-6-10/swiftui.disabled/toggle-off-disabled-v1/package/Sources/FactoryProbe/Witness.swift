#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_disabled_toggle_off: View {
    @State private var enabled = false
    var body: some View {
        Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.switch).disabled(true)
    }
}
