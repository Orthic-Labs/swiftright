#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tf_truncated: View {
    @State private var name = "HelloLongSentenceThatWillNotFit"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 80).padding(10) }
}
