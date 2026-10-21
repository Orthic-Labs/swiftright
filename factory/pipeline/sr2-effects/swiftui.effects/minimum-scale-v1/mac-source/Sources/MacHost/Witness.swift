#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #54, case minimum-scale-v1: one-line Text shrunk to fit by minimumScaleFactor. Row 1 shrinks to about 0.7 (a 20 pt font to about 14 pt), row 2 fits and is
// untouched, row 3 is allowed only 0.8 and truncates after shrinking. SwiftUI's size is continuous, ours moves in half points (9 pt floor), so up to 0.5 pt of
// font size differs: the ink box is gated with the F2 text position tolerances, widened until a CI pair fits them.
struct Witness_e54_minimum_scale_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pulse notch status line").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.5).frame(width: 150, height: 30, alignment: .leading)
            Text("Short").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.5).frame(width: 150, height: 30, alignment: .leading)
            Text("Pulse notch status line").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.8).frame(width: 150, height: 30, alignment: .leading)
        }
        .frame(width: 240, height: 160)
    }
}
