#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R3 (#38), case delay-v1: withAnimation(.snappy.delay(0.2)) widens a bar 100 -> 250 pt.
struct Witness_r3_delay_v1: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.snappy.delay(0.2))) { wide = true } }
    }
}
