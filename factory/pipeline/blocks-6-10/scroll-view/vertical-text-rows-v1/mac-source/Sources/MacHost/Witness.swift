#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

/// The recipe witness (rows of Text in a 120 x 48 vertical ScrollView, content taller than the viewport) on a yellow backdrop so the viewport frame is visible in pixels.
struct Witness_scroll_view_text_rows: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.yellow).frame(width: 120, height: 48)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        Text("Row \(index)").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(width: 120, height: 48)
        }
        .frame(width: 120, height: 48)
        .environment(\.colorScheme, .light)
    }
}
