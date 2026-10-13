#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_shapes_fill_stroke: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 20)
            .environment(\.colorScheme, .light)
    }
}
