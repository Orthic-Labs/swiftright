struct Witness_disabled: View {
    var body: some View {
        Button("Continue") {}.disabled({{disabled}})
            .environment(\.colorScheme, .{{color-scheme}})
    }
}