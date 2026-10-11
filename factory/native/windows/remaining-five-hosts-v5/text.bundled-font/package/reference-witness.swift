struct Witness_text_bundled_font: View {
    var body: some View {
        Text("SwiftRight AV")
            .font(.system(size: {{size}}, weight: .{{weight}}, design: .rounded))
            .lineLimit(2)
            .frame(width: {{width}}, alignment: .leading)
    }
}