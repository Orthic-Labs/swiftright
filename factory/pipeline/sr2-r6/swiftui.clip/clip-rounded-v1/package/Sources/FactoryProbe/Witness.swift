#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)

// SR2 R6 (#41), case clip-rounded-v1: three colour bands clipped to a RoundedRectangle(cornerRadius: 24, style: .circular).
struct Witness_r6_clip_rounded_v1: View {
    var body: some View {
        HStack(spacing: 0) {
            red.frame(width: 60)
            green.frame(width: 60)
            blue.frame(width: 60)
        }
        .frame(width: 180, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
        .frame(width: 240, height: 160)
    }
}
