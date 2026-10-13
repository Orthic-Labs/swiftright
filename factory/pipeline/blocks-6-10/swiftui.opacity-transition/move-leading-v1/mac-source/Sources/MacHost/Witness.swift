#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case move-leading: inserted with `.transition(.move(edge: .leading))` under linear(1 s): it slides in from one view width to the left of its place.
struct Witness_transition_move_leading: View {
    @State private var shown = false
    var body: some View {
        VStack(spacing: 0) {
            if shown { Color.blue.frame(width: 120, height: 40).transition(.move(edge: .leading)) }
        }
        .frame(width: 200, height: 60)
        .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { shown = true } }
    }
}
