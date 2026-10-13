#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_submit: View {
    @State private var name = ""
    @State private var submitted = "none"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { submitted = name }
            Text("submitted: \(submitted)")
            Text("typed: \(name)")
        }.frame(width: 120).padding(10)
    }
}
