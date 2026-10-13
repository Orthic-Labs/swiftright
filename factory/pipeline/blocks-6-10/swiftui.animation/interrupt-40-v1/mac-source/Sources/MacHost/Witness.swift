#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case interrupt-40: a bar widens 100 -> 200 over easeInOut(1 s); at 0.4 s (40 %) a second withAnimation sends it back to 100.
// SwiftUI keeps the first animation running underneath (additive): presented = 100 + first(t) * (1 - second(t - 0.4)). FactoryClock.at runs the action at that manual-clock time.
struct Witness_anim_interrupt: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 200 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear {
                withAnimation(FactoryAnim.wrap(.easeInOut(duration: 1))) { wide = true }
                FactoryClock.at(0.4) { withAnimation(FactoryAnim.wrap(.easeInOut(duration: 1))) { wide = false } }
            }
    }
}
