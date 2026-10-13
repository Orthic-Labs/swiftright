#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_selection_initial: View {
    @State private var sel: Int? = 2
    var body: some View {
        List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 160)
    }
}
