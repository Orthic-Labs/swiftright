#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lrs_sep_hidden_some: View {
    
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowSeparator(i % 2 == 1 ? .hidden : .visible) } }.frame(width: 200, height: 160)
    }
}
