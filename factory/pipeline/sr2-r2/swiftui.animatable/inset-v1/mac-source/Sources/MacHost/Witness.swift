#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R2 (#37), case inset-v1: Circle().inset(by: 0 -> 30) filled, under .linear(duration: 1).
struct Witness_r2_inset_v1: View {
    @State private var amount: CGFloat = 0
    var body: some View {
        Circle().inset(by: amount)
            .fill(Color.blue)
            .frame(width: 140, height: 140)
            .frame(width: 240, height: 160)
            .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { amount = 30 } }
    }
}
