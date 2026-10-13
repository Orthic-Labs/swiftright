#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case opacity-animated: `.opacity(_:)` changed under withAnimation(.easeInOut(duration: 1)): 0.2 -> 1.0.
struct Witness_opacity_animated: View {
    @State private var on = false
    var body: some View {
        Color.blue.frame(width: 120, height: 40).opacity(on ? 1.0 : 0.2)
            .onAppear { withAnimation(FactoryAnim.wrap(.easeInOut(duration: 1))) { on = true } }
    }
}
