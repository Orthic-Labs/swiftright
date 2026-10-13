import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.pixel-ties, case ruler: every edge sits on an exact half device pixel (scale 2.5: an odd number of points is n + 0.5 px)
// and nothing avoids it. Row i (1 pt tall, so its top edge is i pt) has a blue lead of 2i + 1 pt and a 1 pt red mark: the blue far edge
// and the red near edge are at 2i + 1 pt in x (a tie), the red far edge at 2i + 2 pt (not a tie); the row edges at i pt in y tie for every
// odd i. The ties run up to 317 pt, across every run of SwiftUI's value-dependent choice (1 pt down, 3-7 up, 9-25 down, 27-127 up, 129+ down).
struct Witness_pixel_ties_ruler: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<159, id: \.self) { i in
                HStack(spacing: 0) {
                    Color.blue.frame(width: CGFloat(2 * i + 1), height: 1)
                    Color.red.frame(width: 1, height: 1)
                }
            }
        }
        .frame(width: 320, height: 240, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }
}
