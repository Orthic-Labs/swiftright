#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


struct Witness_fp_neg_butt_cap: View {
    var body: some View {
        #if os(Windows)
        Circle().inset(by: 3).trim(from: 0, to: 0.62)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .butt)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
        #else
        Circle().inset(by: 3).trim(from: 0, to: 0.62)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
        #endif
    }
}
