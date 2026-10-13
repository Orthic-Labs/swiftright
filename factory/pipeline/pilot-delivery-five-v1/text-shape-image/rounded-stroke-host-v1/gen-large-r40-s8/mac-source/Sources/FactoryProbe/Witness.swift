#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_shapes_fill_stroke: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 40).stroke(Color.blue, lineWidth: 8).frame(width: 200, height: 140)
            .environment(\.colorScheme, .light)
    }
}
