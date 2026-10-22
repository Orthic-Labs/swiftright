#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #79, case button-pressed-dark-v1: button-pressed-v1 in dark mode (dark appearance on the Mac, dark scheme on both): the four built-in Button styles at rest and with the
// primary mouse button held down. Each label is 84 pt wide so the bodies do not depend on the text face.
struct Witness_g79_button_pressed_dark_v1: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 14) {
                Button { } label: { Text("Bordered").frame(width: 84) }.buttonStyle(.bordered)
                Button { } label: { Text("Prominent").frame(width: 84) }.buttonStyle(.borderedProminent)
                Button { } label: { Text("Plain").frame(width: 84) }.buttonStyle(.plain)
                Button { } label: { Text("Borderless").frame(width: 84) }.buttonStyle(.borderless)
            }
        }
        .frame(width: 320, height: 240).environment(\.colorScheme, .dark)
    }
}
