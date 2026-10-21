#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

private let e54Red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let e54Green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let e54Blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let e54Gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
private let e54Orange = Color(.sRGB, red: 1.0, green: 0.6, blue: 0.0, opacity: 1)

// Issue #54, case brightness-pixel-v1: brightness(0.2) on a colour and a circle, brightness(-0.2) on a rounded rectangle; an unadjusted sibling.
// Every amount is a whole number of levels (0.2 x 255 = 51), so the expected channel values are exact.
struct Witness_e54_brightness_pixel_v1: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                e54Blue.frame(width: 50, height: 30)
                Circle().fill(e54Red).frame(width: 30, height: 30)
            }.brightness(0.2)
            RoundedRectangle(cornerRadius: 6, style: .circular).fill(e54Green).frame(width: 50, height: 50).brightness(-0.2)
            e54Gray.frame(width: 40, height: 40)
        }
        .frame(width: 240, height: 160)
    }
}
