struct Witness_round2_context_menu: View {
    @State private var chosen = false
    var body: some View {
        Text(chosen ? "Chosen" : "Open menu")
            .contextMenu { Button("Choose") { chosen = true } }
    }
}
