#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_scroll_view_horizontal: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.red).frame(width: 40, height: 60)
                Rectangle().fill(Color.blue).frame(width: 40, height: 60)
                Rectangle().fill(Color.green).frame(width: 40, height: 60)
                Rectangle().fill(Color.orange).frame(width: 40, height: 60)
                Rectangle().fill(Color.purple).frame(width: 40, height: 60)
            }
        }.frame(width: 100, height: 60)
            .environment(\.colorScheme, .light)
    }
}
