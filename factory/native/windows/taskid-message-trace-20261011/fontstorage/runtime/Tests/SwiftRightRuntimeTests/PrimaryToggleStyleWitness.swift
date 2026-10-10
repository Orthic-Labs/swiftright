import SwiftRightRuntime

struct Witness_toggle: View {
    @State private var enabled = true
    var body: some View {
        Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.automatic)
    }
}
