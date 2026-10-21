#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #54, case spring-removal-v1: .bouncy widens a bar 100 -> 250 pt; at 0.2 s a second .bouncy sends it back to 100. The interrupted spring continues from the
// presented position and velocity and is removed once it stays within one device pixel of 100 (the same rule as a fresh spring). The frames from 0.6 s sample the
// tail: a runtime that removed it early (the former relative 1 % rule left up to 5 px) snaps to 100 while SwiftUI still has pixels to go.
struct Witness_e54_spring_removal_v1: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 250 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear {
                withAnimation(FactoryAnim.wrap(.bouncy)) { wide = true }
                FactoryClock.at(0.2) { withAnimation(FactoryAnim.wrap(.bouncy)) { wide = false } }
            }
    }
}
