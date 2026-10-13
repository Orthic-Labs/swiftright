#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case disables-animations: a transaction with disablesAnimations (and no animation of its own) silences `.animation(_:value:)`,
// so the bar jumps to 200 pt; a second bar under an explicit transaction that also sets disablesAnimations still animates (measured on SwiftUI).
struct Witness_anim_disables: View {
    @State private var wide = false
    @State private var wide2 = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.blue.frame(width: wide ? 200 : 100, height: 20)
                .animation(FactoryAnim.wrap(.linear(duration: 1)), value: wide)
            Color.red.frame(width: wide2 ? 200 : 100, height: 20)
        }
        .frame(width: 300, height: 60, alignment: .leading)
        .onAppear {
            var silenced = Transaction()
            silenced.disablesAnimations = true
            withTransaction(silenced) { wide = true }
            // a separate update: state changes in one flush all take the last explicit transaction (decision C7)
            FactoryClock.at(0) {
                var explicit = Transaction(animation: FactoryAnim.wrap(.linear(duration: 1)))
                explicit.disablesAnimations = true
                withTransaction(explicit) { wide2 = true }
            }
        }
    }
}
