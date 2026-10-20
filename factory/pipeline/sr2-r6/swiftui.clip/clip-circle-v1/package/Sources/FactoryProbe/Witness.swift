#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let red = Color(.sRGB, red: 1.0, green: 0.2, blue: 0.2, opacity: 1)
private let green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2, opacity: 1)
private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 1.0, opacity: 1)

// SR2 R6 (#41), case clip-circle-v1: a colour and a stroked ring that straddles the edge (110 pt, 16 pt line: 126 pt outside, 94 pt inside), clipped to a 120 pt Circle.
struct Witness_r6_clip_circle_v1: View {
    var body: some View {
        ZStack {
            blue
            Circle().stroke(red, lineWidth: 16).frame(width: 110, height: 110)
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .frame(width: 240, height: 160)
    }
}
