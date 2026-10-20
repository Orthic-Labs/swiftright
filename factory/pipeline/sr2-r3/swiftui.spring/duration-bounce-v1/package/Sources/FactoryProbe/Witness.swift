#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R3 (#38), case duration-bounce-v1: withAnimation(.spring(duration: 0.35, bounce: -0.3)) widens a bar 100 -> 250 pt.
struct Witness_r3_duration_bounce_v1: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.spring(duration: 0.35, bounce: -0.3))) { wide = true } }
    }
}
