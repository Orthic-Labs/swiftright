#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R3 (#38), case bouncy-v1: withAnimation(.bouncy) widens a bar 100 -> 250 pt.
struct Witness_r3_bouncy_v1: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.bouncy)) { wide = true } }
    }
}
