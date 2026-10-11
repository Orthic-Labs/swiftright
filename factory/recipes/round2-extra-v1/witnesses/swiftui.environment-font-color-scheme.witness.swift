struct Witness_round2_environment: View {
    var body: some View {
        VStack { Text("Inherited environment"); Text("Inherited child") }
            .environment(\.font, .system(size: {{font-size}}))
            .environment(\.colorScheme, .{{scheme}})
    }
}
