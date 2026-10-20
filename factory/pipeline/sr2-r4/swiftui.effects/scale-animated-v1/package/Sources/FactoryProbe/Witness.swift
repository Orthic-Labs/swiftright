#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let unusedRed = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)

// SR2 R4 (#39), case scale-animated-v1: a bar scaled 1 -> 1.6 about its leading edge under .linear(duration: 1) on the manual clock.
struct Witness_r4_scale_animated_v1: View {
    @State private var big = false
    var body: some View {
        Color.blue.frame(width: 100, height: 40)
            .scaleEffect(x: big ? 1.6 : 1, y: 1, anchor: .leading)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { big = true } }
    }
}
