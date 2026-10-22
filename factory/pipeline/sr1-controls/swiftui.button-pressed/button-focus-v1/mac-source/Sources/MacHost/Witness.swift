#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #77, case button-pressed-v1: the four built-in Button styles, each captured at rest and with the primary mouse button held down on it (ops down / up).
// Each label is 84 pt wide so the body width does not depend on the text face (Segoe UI vs SF would otherwise make the bodies differ).
struct Witness_g79_button_focus_v1: View {
    var body: some View {
        VStack(spacing: 14) {
            Button { } label: { Text("Bordered").frame(width: 84) }.buttonStyle(.bordered)
            Button { } label: { Text("Prominent").frame(width: 84) }.buttonStyle(.borderedProminent)
            Button { } label: { Text("Plain").frame(width: 84) }.buttonStyle(.plain)
            Button { } label: { Text("Borderless").frame(width: 84) }.buttonStyle(.borderless)
        }
        .padding(20).frame(width: 200, height: 200)
    }
}
