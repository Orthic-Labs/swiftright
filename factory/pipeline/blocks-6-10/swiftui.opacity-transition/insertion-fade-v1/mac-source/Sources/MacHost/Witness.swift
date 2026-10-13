#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case insertion-fade: a blue 120 x 40 view is inserted under withAnimation(.linear(duration: 1)) with `.transition(.opacity)`: its alpha follows the animation.
struct Witness_transition_opacity_insert: View {
    @State private var shown = false
    var body: some View {
        VStack(spacing: 0) {
            if shown { Color.blue.frame(width: 120, height: 40).transition(.opacity) }
        }
        .frame(width: 200, height: 60)
        .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { shown = true } }
    }
}
