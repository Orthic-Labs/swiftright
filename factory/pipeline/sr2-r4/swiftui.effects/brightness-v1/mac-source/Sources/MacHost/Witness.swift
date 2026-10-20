#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)

// SR2 R4 (#39), case brightness-v1: brightness(0.2) on a colour and a circle, brightness(-0.3) on a rounded rectangle; an unadjusted sibling.
struct Witness_r4_brightness_v1: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                blue.frame(width: 50, height: 30)
                Circle().fill(red).frame(width: 30, height: 30)
            }.brightness(0.2)
            RoundedRectangle(cornerRadius: 6, style: .circular).fill(green).frame(width: 50, height: 50).brightness(-0.3)
            gray.frame(width: 40, height: 40)
        }
        .frame(width: 240, height: 160)
    }
}
