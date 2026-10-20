#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


// Negative control (expectFail): the Windows stroke is 0.4 pt wider (1 px at scale 2.5, 0.5 px per edge), a difference that stays
// inside the 1 px edge band, so only the band statistics (over-share, mean) can reject it.
#if os(Windows)
private let negWidth: CGFloat = 6.4
#else
private let negWidth: CGFloat = 6
#endif

struct Witness_fp_neg_width_04: View {
    var body: some View {
        Circle().inset(by: 3).trim(from: 0, to: 0.62)
            .stroke(blue, style: StrokeStyle(lineWidth: negWidth, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
    }
}
