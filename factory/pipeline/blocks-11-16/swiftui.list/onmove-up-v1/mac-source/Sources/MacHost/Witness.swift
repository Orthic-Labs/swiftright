#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_onmove_up: View {
    @State private var items = [0, 1, 2, 3, 4]
    @State private var sel: Int? = nil
    var body: some View {
        List(selection: $sel) {
            ForEach(items, id: \.self) { i in Text("Row \(i)").tag(i) }
            .onMove { source, destination in items.move(fromOffsets: source, toOffset: destination) }
        }.frame(width: 200, height: 160)
    }
}
