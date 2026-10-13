#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.opacity-transition, case removal-move: removed with `.transition(.move(edge: .leading))`: it leaves one view width towards the leading edge, without fading.
struct Witness_removal_move: View {
    @State private var shown = true
    var body: some View {
        VStack(spacing: 0) {
            if shown { Color.blue.frame(width: 120, height: 40).transition(.move(edge: .leading)) }
            Color.red.frame(width: 60, height: 20)
        }
        .frame(width: 200, height: 80, alignment: .top)
        .onAppear { FactoryClock.at(0) { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { shown = false } } }
    }
}