#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_automatic: View {
    @State private var name = "Hello"
    var body: some View { TextField("Name", text: $name).frame(width: 120).padding(10) }
}
