#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_plain_selected: View {
    @State private var sel: Int? = 1
    var body: some View {
        List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.listStyle(.plain).frame(width: 200, height: 160)
    }
}
