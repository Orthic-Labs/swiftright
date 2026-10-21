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

// Issue #54, case paint-linewidth-v1: a ring and a rectangle outline whose stroke grows from 2 to 10 pt while the colour goes from green to orange, under
// .linear(duration: 1). The line width is interpolated linearly, the colour as in paint-colour-v1.
struct Witness_e54_paint_linewidth_v1: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 30) {
            Circle().stroke(on ? e54Orange : e54Green, lineWidth: on ? 10 : 2).frame(width: 60, height: 60)
            Rectangle().stroke(on ? e54Orange : e54Green, lineWidth: on ? 10 : 2).frame(width: 60, height: 60)
        }
        .frame(width: 240, height: 160)
        .onAppear { withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { on = true } }
    }
}
