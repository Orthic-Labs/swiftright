#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

enum Field: Hashable { case first, second }

struct Witness_focus_shifttab: View {
    @State private var a = "one"
    @State private var b = "two"
    @FocusState private var focus: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("First", text: $a).textFieldStyle(.roundedBorder).focused($focus, equals: .first)
            TextField("Second", text: $b).textFieldStyle(.roundedBorder).focused($focus, equals: .second)
            Text("focus: \(focus == .first ? "first" : focus == .second ? "second" : "none")")
        }.frame(width: 120).padding(10)
    }
}
