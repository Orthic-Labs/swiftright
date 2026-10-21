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

// Issue #54, case paint-colour-v1: a state change under .linear(duration: 1) turns a rectangle fill, a Color view, a circle fill and an implicit (foreground style) fill
// from red to blue. SwiftUI interpolates the resolved colour; the mid frames (0.25, 0.5, 0.75) tell gamma-encoded from linear-light interpolation:
// at 0.5 the red channel reads 153 (gamma-encoded) or 187 (linear light), and a runtime that interpolates the wrong way fails by 34 levels in the interior.
struct Witness_e54_paint_colour_v1: View {
    @State private var on = false
    var body: some View {
        VStack(spacing: 10) {
            Rectangle().fill(on ? e54Blue : e54Red).frame(width: 80, height: 30)
            (on ? e54Blue : e54Red).frame(width: 80, height: 30)
            Circle().fill(on ? e54Blue : e54Red).frame(width: 30, height: 30)
            Rectangle().foregroundStyle(on ? e54Blue : e54Red).frame(width: 80, height: 20)
        }
        .frame(width: 240, height: 160)
        .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { on = true } }
    }
}
