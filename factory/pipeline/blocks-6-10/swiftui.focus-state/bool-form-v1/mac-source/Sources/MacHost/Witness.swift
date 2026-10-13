#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_focus_bool: View {
    @State private var a = "one"
    @FocusState private var flag: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $a).textFieldStyle(.roundedBorder).focused($flag)
            Text("flag: \(flag ? "true" : "false")")
            Button("Focus") { flag = true }.frame(width: 100, height: 24)
            Button("Blur") { flag = false }.frame(width: 100, height: 24)
        }.frame(width: 120).padding(10)
    }
}
