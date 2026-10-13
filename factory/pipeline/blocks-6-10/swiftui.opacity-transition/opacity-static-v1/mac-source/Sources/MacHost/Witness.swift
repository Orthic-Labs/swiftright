#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case opacity-static: `.opacity(0.5)` on flat colours (a nested one multiplies: 0.5 * 0.5).
struct Witness_opacity_static: View {
    var body: some View {
        VStack(spacing: 8) {
            Color.blue.frame(width: 120, height: 40).opacity(0.5)
            Color.red.frame(width: 120, height: 40).opacity(0.5).opacity(0.5)
            Color.green.frame(width: 120, height: 40)
        }
    }
}
