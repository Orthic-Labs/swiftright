#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #60, case progress-determinate-v1: a linear determinate ProgressView at 0.3 and 0.7 of its total, 200 pt wide. The bar metrics (6 pt capsule track and fill) are GUESSED from
// NSProgressIndicator and not measured on macOS 27; this case is what measures them.
struct Witness_p60_progress_determinate_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: 0.3).frame(width: 200)
            ProgressView(value: 0.7).frame(width: 200)
        }
        .frame(width: 240, height: 120)
    }
}
