#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

// Block swiftui.compat, case empty-withanimation: an empty withAnimation(.linear(duration: 1)) {} (no writes, no nested block), then a separate plain write x = 1 that
// drives the orange bar from 10 to 50 pt. The blue bar is driven by a plain write y = 1 with no withAnimation at all (the always-plain reference). At t = 0.5 the orange bar
// is about 30 pt if the empty block's animation leaked to the next plain write, and 50 pt if it did not; the blue bar is 50 pt in both cases. Nothing here is asserted from SwiftUI documentation.
struct Witness_co_empty: View {
    @State private var x = 0
    @State private var y = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.orange.frame(width: CGFloat(x) * 40 + 10, height: 10)
            Color.blue.frame(width: CGFloat(y) * 40 + 10, height: 10)
        }
        .frame(width: 200, height: 80, alignment: .topLeading)
        .onAppear {
            FactoryClock.at(0) {
                withAnimation(FactoryAnim.wrap(.linear(duration: 1))) {}
                x = 1
                y = 1
            }
        }
    }
}
