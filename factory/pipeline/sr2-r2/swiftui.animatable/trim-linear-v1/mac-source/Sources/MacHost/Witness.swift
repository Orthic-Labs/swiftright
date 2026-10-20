#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R2 (#37), case trim-linear-v1: Circle().trim(from:to:) ring 0.1 -> 0.9 under .linear(duration: 1), round caps (the notch ring gauge).
struct Witness_r2_trim_linear_v1: View {
    @State private var end: CGFloat = 0.1
    var body: some View {
        Circle().trim(from: 0, to: end)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .frame(width: 120, height: 120)
            .frame(width: 240, height: 160)
            .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { end = 0.9 } }
    }
}
