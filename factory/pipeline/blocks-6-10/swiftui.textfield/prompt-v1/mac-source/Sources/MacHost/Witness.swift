#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_prompt: View {
    @State private var name = ""
    var body: some View { TextField("Name", text: $name, prompt: Text("Enter")).textFieldStyle(.roundedBorder).frame(width: 120).padding(10) }
}
