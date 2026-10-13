#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case easeinout-samples: withAnimation(.easeInOut(duration: 1)) widens a blue bar 100 -> 200 pt; sampled at 0/25/50/75/100 %.
// FactoryAnim.wrap is the host hook (Windows: the animation as written; Mac clock host: the same animation evaluated at the manual clock).
struct Witness_anim_easeinout: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 200 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.easeInOut(duration: 1))) { wide = true } }
    }
}
