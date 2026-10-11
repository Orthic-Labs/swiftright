struct Witness_round2_popover: View {
    @State private var shown = false
    var body: some View {
        Button("Open popover") { shown = true }
            .popover(isPresented: $shown) { Text("Popover content") }
    }
}
