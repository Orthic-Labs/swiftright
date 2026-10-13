#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_plain: View {
    @State private var name = "Hello"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.plain).frame(width: 120).padding(10) }
}
