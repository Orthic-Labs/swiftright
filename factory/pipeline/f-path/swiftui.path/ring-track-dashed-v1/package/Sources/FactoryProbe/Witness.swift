#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51


struct Witness_fp_ring_track_dashed: View {
    var body: some View {
        Circle().inset(by: 3)
            .stroke(blue.opacity(0.7), style: StrokeStyle(lineWidth: 6, dash: [4, 2])).rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
    }
}
