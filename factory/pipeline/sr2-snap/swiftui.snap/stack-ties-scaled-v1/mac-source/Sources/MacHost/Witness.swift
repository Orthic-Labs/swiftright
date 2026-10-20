#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #44 probe: a VStack (spacing 2.6) of seven colour rows whose heights put the rows on varied half-pixel ties at scale 2.5, under scaleEffect(1.4).
struct Witness_stack_ties_scaled_v1: View {
    var body: some View {
        VStack(spacing: 2.6) {
            Color(.sRGB, red: 1.0, green:  0.2, blue:  0.2, opacity: 1).frame(width: 60, height: 11.2)
            Color(.sRGB, red: 0.2, green:  0.8, blue:  0.2, opacity: 1).frame(width: 60, height: 13)
            Color(.sRGB, red: 0.2, green:  0.4, blue:  1.0, opacity: 1).frame(width: 60, height: 7.4)
            Color(.sRGB, red: 1.0, green:  0.6, blue:  0.0, opacity: 1).frame(width: 60, height: 9)
            Color(.sRGB, red: 0.6, green:  0.2, blue:  0.9, opacity: 1).frame(width: 60, height: 12.6)
            Color(.sRGB, red: 0.1, green:  0.7, blue:  0.7, opacity: 1).frame(width: 60, height: 10)
            Color(.sRGB, red: 0.9, green:  0.9, blue:  0.1, opacity: 1).frame(width: 60, height: 8.2)
        }
        .scaleEffect(1.4)
        .frame(width: 240, height: 160)
    }
}
