#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R2 (#37), case corner-radius-v1: RoundedRectangle(cornerRadius: 4 -> 40, style: .circular) under .linear(duration: 1).
struct Witness_r2_corner_radius_v1: View {
    @State private var round = false
    var body: some View {
        RoundedRectangle(cornerRadius: round ? 40 : 4, style: .circular)
            .fill(Color.blue)
            .frame(width: 180, height: 100)
            .frame(width: 240, height: 160)
            .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { round = true } }
    }
}
