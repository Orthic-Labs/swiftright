#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lrs_plain_selected_bg: View {
    @State private var sel: Int? = 2
    var body: some View {
        List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowBackground(Color.red).tag(i) } }.listStyle(.plain).frame(width: 200, height: 160)
    }
}
