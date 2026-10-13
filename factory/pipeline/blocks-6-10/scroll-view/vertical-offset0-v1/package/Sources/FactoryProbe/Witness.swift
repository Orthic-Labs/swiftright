#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_scroll_view: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: 40)
                Rectangle().fill(Color.blue).frame(height: 40)
                Rectangle().fill(Color.green).frame(height: 40)
                Rectangle().fill(Color.orange).frame(height: 40)
                Rectangle().fill(Color.purple).frame(height: 40)
            }
        }.frame(width: 120, height: 100)
            .environment(\.colorScheme, .light)
    }
}
