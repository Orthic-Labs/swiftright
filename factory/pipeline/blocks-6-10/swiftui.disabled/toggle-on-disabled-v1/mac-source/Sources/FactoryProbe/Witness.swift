#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_disabled_toggle_on: View {
    @State private var enabled = true
    var body: some View {
        Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.switch).disabled(true)
    }
}
