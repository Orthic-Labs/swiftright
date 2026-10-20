#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)

// SR2 R4 (#39), case scale-center-v1: scaleEffect(1.4) about the centre of a rounded rectangle and a filled 32 pt circle (centred on whole pixels: a 30 pt circle centred on a half pixel is 1 px narrower in runtime layout, issue #44).
struct Witness_r4_scale_center_v1: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .circular).fill(blue).frame(width: 80, height: 30)
            Circle().fill(red).frame(width: 32, height: 32)
        }
        .scaleEffect(1.4)
        .frame(width: 240, height: 160)
    }
}
