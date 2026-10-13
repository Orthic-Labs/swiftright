#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_shapes_rectangle_fill: View {
    var body: some View {
        Rectangle().fill(Color.red).frame(width: 40, height: 20)
            .environment(\.colorScheme, .light)
    }
}
