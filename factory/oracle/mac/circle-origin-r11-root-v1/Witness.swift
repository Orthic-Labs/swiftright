#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

/// Source-bound Circle pilot. Keep frame & color scheme explicit.
struct Witness_circle_fixed: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 40, height: 40)
            .environment(\.colorScheme, .light)
    }
}
