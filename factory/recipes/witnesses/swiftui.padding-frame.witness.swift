struct Witness_padding_frame: View {
    var body: some View {
        Text("Box").padding({{padding}}).frame(width: {{width}}, height: 40, alignment: .{{alignment}})
    }
}