struct Witness_tinos_bundled_text_pilot: View {
    var body: some View {
        Text({{text}})
            .font(.custom("Tinos-Regular", size: {{size}}))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: {{width}}, alignment: .leading)
    }
}
