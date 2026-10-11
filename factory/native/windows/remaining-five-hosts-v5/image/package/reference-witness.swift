struct Witness_image: View {
    var body: some View {
        Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 32, height: 32)
            .foregroundStyle(.yellow)
            .environment(\.displayScale, {{scale}})
            .environment(\.colorScheme, .{{color-scheme}})
    }
}