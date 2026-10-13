#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case default-spring: withAnimation(.default) (a 0.5 s spring without bounce) widens a bar 100 -> 250 pt.
struct Witness_anim_default_spring: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(FactoryAnim.wrap(.default)) { wide = true } }
    }
}
