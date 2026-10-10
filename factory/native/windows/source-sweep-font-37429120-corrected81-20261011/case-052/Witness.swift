#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_shapes_fill_stroke: View {
    var body: some View {
        Rectangle().fill(Color.red).frame(width: 40, height: 20)
            .environment(\.colorScheme, .dark)
    }
}
