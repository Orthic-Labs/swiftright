#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case linear-width: withAnimation(.linear(duration: 1)) changes a blue bar from 100 to 200 pt wide.
// The bar is pinned to the leading edge of a fixed 300x60 field, so only its trailing edge moves. FactoryAnim.wrap is the host hook
// (Windows: the animation as written; Mac clock host: the same animation evaluated at the manual clock).
struct Witness_anim_linear_width: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 200 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { wide = true } }
    }
}
