#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #77, case button-pressed-v1: the four built-in Button styles, each captured at rest and with the primary mouse button held down on it (ops down / up).
// Layout (points, in a 200 x 200 frame centred in the 320 x 240 host): bordered (60,39,80,24), borderedProminent (57,77,86,24), plain (85.5,115,29.5,16), borderless (67.5,145,65,16).
struct Witness_g77_button_pressed_v1: View {
    var body: some View {
        VStack(spacing: 14) {
            Button("Bordered") {}.buttonStyle(.bordered)
            Button("Prominent") {}.buttonStyle(.borderedProminent)
            Button("Plain") {}.buttonStyle(.plain)
            Button("Borderless") {}.buttonStyle(.borderless)
        }
        .padding(20).frame(width: 200, height: 200)
    }
}
