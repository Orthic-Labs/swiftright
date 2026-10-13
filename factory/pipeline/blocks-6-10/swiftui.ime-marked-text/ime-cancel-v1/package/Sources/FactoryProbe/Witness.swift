#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ime_cancel: View {
    @State private var text = "ab"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $text).textFieldStyle(.roundedBorder)
            Text("bound: \(text)")
        }.frame(width: 120).padding(10)
    }
}
