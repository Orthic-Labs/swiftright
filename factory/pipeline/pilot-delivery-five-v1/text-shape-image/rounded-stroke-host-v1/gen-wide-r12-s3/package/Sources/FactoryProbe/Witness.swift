#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_shapes_fill_stroke: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 3).frame(width: 200, height: 60)
            .environment(\.colorScheme, .light)
    }
}
