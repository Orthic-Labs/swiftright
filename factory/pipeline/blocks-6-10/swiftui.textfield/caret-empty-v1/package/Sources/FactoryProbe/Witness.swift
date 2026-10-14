#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_caret: View {
    @State private var name = ""
    var body: some View { TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 120).padding(10) }
}
