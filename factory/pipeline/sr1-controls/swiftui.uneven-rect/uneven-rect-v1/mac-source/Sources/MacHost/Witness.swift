#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #84, case uneven-rect-v1: UnevenRoundedRectangle, continuous corners (default) with four different radii, a circular one with two, and a stroked one.
struct Witness_g84_uneven_rect_v1: View {
    var body: some View {
        VStack(spacing: 20) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 30, topTrailingRadius: 0).fill(Color.blue).frame(width: 140, height: 60)
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 24, topTrailingRadius: 0, style: .circular).fill(Color.green).frame(width: 140, height: 50)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 0, topTrailingRadius: 12).stroke(Color.red, lineWidth: 3).frame(width: 140, height: 50)
        }
    }
}
