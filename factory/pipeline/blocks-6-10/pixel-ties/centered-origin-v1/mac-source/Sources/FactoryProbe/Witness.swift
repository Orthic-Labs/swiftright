import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.pixel-ties, case centered-origin: the root is 298 x 218 pt, centred in the 320 x 240 pt canvas at (11, 11) pt, which is
// 27.5 px: the origin itself is an exact half pixel, so every edge at an even offset inside the root (11 + even = odd points) ties, and the
// root's own far edges (309 pt, 229 pt) tie too. Nothing avoids it. A diagonal of 3 pt squares steps 12 pt in x and 8 pt in y.
struct Witness_pixel_ties_centered: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.blue.frame(width: 298, height: 218)
            ForEach(0..<24, id: \.self) { i in
                Color.green.frame(width: 3, height: 3)
                    .padding(.leading, CGFloat(12 * i)).padding(.top, CGFloat(8 * i))
                    .frame(width: 298, height: 218, alignment: .topLeading)
            }
            Color.red.frame(width: 9, height: 9).padding(.leading, 5).padding(.top, 197)
                .frame(width: 298, height: 218, alignment: .topLeading)
            Color.orange.frame(width: 21, height: 11).padding(.trailing, 7).padding(.bottom, 3)
                .frame(width: 298, height: 218, alignment: .bottomTrailing)
        }
        .frame(width: 298, height: 218)
        .environment(\.colorScheme, .light)
    }
}
