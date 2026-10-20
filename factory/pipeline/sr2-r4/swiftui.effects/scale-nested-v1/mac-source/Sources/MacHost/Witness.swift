#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)
private let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)

// SR2 R4 (#39), case scale-nested-v1: nested scaleEffect(x: 2, y: 0.5) inside scaleEffect(0.8, anchor: .bottom).
struct Witness_r4_scale_nested_v1: View {
    var body: some View {
        Capsule().fill(green).frame(width: 60, height: 40)
            .scaleEffect(x: 2, y: 0.5)
            .scaleEffect(0.8, anchor: .bottom)
            .frame(width: 240, height: 160)
    }
}
