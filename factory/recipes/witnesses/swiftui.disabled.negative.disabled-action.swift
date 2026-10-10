struct Witness_swiftui_disabled_negative_disabled_action: View {
    @State private var actionCount = 0
    var body: some View {
        VStack {
            Button("Continue") { actionCount += 1 }.disabled(true)
            Text("\(actionCount)")
        }
    }
}