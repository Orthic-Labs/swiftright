#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R3 (#38), case response-v1: withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) widens a bar 100 -> 250 pt.
struct Witness_r3_response_v1: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.spring(response: 0.4, dampingFraction: 0.7))) { wide = true } }
    }
}
