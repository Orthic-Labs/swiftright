struct Witness_shapes_fill_stroke: View {
    var body: some View {
        {{shape}}.{{style}}.frame(width: 40, height: 20)
            .environment(\.colorScheme, .{{color-scheme}})
    }
}