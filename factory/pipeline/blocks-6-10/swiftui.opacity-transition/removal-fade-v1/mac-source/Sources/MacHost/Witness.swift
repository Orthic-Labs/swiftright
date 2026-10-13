#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case removal-fade: a blue 120 x 40 view is removed under withAnimation(.linear(duration: 1)) with `.transition(.opacity)`:
// it stays in place and fades out while its red sibling moves up (measured: the removed view keeps its last frame).
struct Witness_removal_fade: View {
    @State private var shown = true
    var body: some View {
        VStack(spacing: 0) {
            if shown { Color.blue.frame(width: 120, height: 40).transition(.opacity) }
            Color.red.frame(width: 60, height: 20)
        }
        .frame(width: 200, height: 80, alignment: .top)
        .onAppear { FactoryClock.at(0) { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { shown = false } } }
    }
}