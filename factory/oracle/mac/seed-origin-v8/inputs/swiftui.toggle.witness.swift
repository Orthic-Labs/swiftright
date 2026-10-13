struct Witness_toggle: View {
    @State private var enabled = {{initial}}
    var body: some View {
        Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.{{style}})
    }
}