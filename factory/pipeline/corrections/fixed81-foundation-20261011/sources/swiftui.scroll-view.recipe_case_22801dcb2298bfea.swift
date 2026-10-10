#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_scroll_view: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<4, id: \.self) { index in Text("Row \(index)").frame(maxWidth: .infinity, alignment: .leading) }
            }
        }.frame(width: 120, height: 48)
    }
}
