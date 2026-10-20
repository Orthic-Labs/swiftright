#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)          // 255, 51, 51
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)        // 51, 204, 51
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)         // 51, 102, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.5, blue: 0.0, opacity: 1)       // 255, 128, 0
private let purple = Color(.sRGB, red: 0.6, green: 0.2, blue: 0.9, opacity: 1)       // 153, 51, 230
private let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)         // 128, 128, 128

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(8).background(gray)
    }
}

struct Witness_r1_viewmodifier_v1: View {
    var body: some View {
        Rectangle().fill(blue).frame(width: 40, height: 20)
            .modifier(CardStyle())
            .frame(width: 240, height: 160)
    }
}
