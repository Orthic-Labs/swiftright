#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_round2_ime: View {
    @State private var value = ""
    var body: some View {
        VStack { TextField(text: $value, prompt: Text("Compose")) { Text("Compose") }; Text(value) }
    }
}
