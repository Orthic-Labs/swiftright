#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #54, case scale-nonuniform-v1: scaleEffect(x:y:) and scaleEffect(CGSize) on a capsule, a rounded rectangle and a circle. SwiftUI scales the drawn geometry, so the
// capsule keeps its straight edge with elliptical ends and the circle becomes an ellipse. Fills only: a stroke is widened by the geometric mean of the two factors on
// Windows (not per axis), which this case does not cover.
struct Witness_e54_scale_nonuniform_v1: View {
    var body: some View {
        HStack(spacing: 34) {
            Capsule(style: .circular).fill(Color.blue).frame(width: 36, height: 20).scaleEffect(x: 1.6, y: 0.5)
            RoundedRectangle(cornerRadius: 8, style: .circular).fill(Color.orange).frame(width: 30, height: 40).scaleEffect(CGSize(width: 1.5, height: 0.7), anchor: .leading)
            Circle().fill(Color.green).frame(width: 30, height: 30).scaleEffect(x: 0.6, y: 1.5, anchor: .bottom)
        }
        .frame(width: 240, height: 160)
    }
}
