#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)

// Issue #60, case capsule-stroke-v1: stroked pills (Capsule().stroke) at line widths 1, 2 and 4, horizontal and vertical.
struct Witness_g60_capsule_stroke_v1: View {
    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 18) {
                Capsule().stroke(blue, lineWidth: 1).frame(width: 120, height: 30)
                Capsule().stroke(blue, lineWidth: 2).frame(width: 120, height: 30)
                Capsule().stroke(blue, lineWidth: 4).frame(width: 120, height: 30)
            }
            Capsule().stroke(blue, lineWidth: 2).frame(width: 34, height: 130)
        }
    }
}
