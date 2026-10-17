#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

// Block swiftui.compat, case settles-only-removal: an outer withAnimation(.linear(duration: 1)) whose only write is inside a nested withAnimation(nil), then a
// separate plain write that removes a view with an opacity transition. Whether the outer transaction governs that later removal is what the Mac capture decides:
// the blue bar fades (a ghost at half opacity at t = 0.5) if it does, and is gone at once if it does not. Nothing here is asserted from SwiftUI documentation.
struct Witness_co_settles: View {
    @State private var x = 0
    @State private var shown = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.orange.frame(width: CGFloat(x) * 20 + 10, height: 6)
            VStack(spacing: 0) {
                if shown { Color.blue.frame(width: 60, height: 20).transition(.opacity) }
            }.frame(width: 60, height: 20, alignment: .top)
        }
        .frame(width: 200, height: 80, alignment: .topLeading)
        .onAppear {
            FactoryClock.at(0) {
                withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { withAnimation(nil) { x = 1 } }
                shown = false
            }
        }
    }
}
