#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #82, case shadow-v1: .shadow on a rectangle (radius 8, default colour), on a rounded rectangle with an offset, and on a circle with a red shadow.
struct Witness_g82_shadow_v1: View {
    var body: some View {
        HStack(spacing: 40) {
            Rectangle().fill(Color.white).frame(width: 50, height: 50).shadow(radius: 8)
            RoundedRectangle(cornerRadius: 10, style: .circular).fill(Color.blue).frame(width: 60, height: 50).shadow(color: .black.opacity(0.5), radius: 5, x: 4, y: 6)
            Circle().fill(Color.green).frame(width: 50, height: 50).shadow(color: .red, radius: 3, x: -3, y: 3)
        }
    }
}
