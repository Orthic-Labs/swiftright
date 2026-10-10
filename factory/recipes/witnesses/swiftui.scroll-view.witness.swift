struct Witness_scroll_view: View {
    var body: some View {
        ScrollView(.{{axis}}) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<{{content-count}}, id: \.self) { index in Text("Row \(index)").frame(maxWidth: .infinity, alignment: .leading) }
            }
        }.frame(width: 120, height: 48)
    }
}