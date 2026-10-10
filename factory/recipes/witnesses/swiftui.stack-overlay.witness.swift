struct Witness_stack_overlay: View {
    var body: some View {
        ZStack(alignment: .{{alignment}}) {
            Rectangle().fill(Color.blue).frame(width: 48, height: 32)
            Circle().fill(Color.red).frame(width: 12, height: 12)
        }.overlay(alignment: .bottomTrailing) { Text("+") }
            .environment(\.colorScheme, .{{color-scheme}})
    }
}