#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.animation, case animation-value: `.animation(_:value:)` animates a plain (unanimated) state change below it, easeIn(1 s), 100 -> 200 pt.
struct Witness_anim_modifier_value: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 200 : 100, height: 40)
            .animation(FactoryAnim.wrap(.easeIn(duration: 1)), value: wide)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { wide = true }
    }
}
