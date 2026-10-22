#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #77, case button-pressed-v1: the four built-in Button styles, each captured at rest and with the primary mouse button held down on it (ops down / up).
// Each label is 84 pt wide so the body width does not depend on the text face (Segoe UI vs SF would otherwise make the bodies differ).
struct Witness_g81_button_focus_initial_v1: View {
    @FocusState private var focus: Int?
    var body: some View {
        VStack(spacing: 14) {
            Button { } label: { Text("Bordered").frame(width: 84) }.buttonStyle(.bordered).focused($focus, equals: 0)
            Button { } label: { Text("Prominent").frame(width: 84) }.buttonStyle(.borderedProminent).focused($focus, equals: 1)
            Button { } label: { Text("Plain") }.buttonStyle(.plain).focused($focus, equals: 2)
            Button { } label: { Text("Borderless") }.buttonStyle(.borderless).focused($focus, equals: 3)
            TextField("Field", text: .constant("")).frame(width: 120).focused($focus, equals: 4)
        }
        .padding(20).frame(width: 200, height: 200)
        // Escape clears the focus (so the case ends with nothing focused: the Mac's cacheDisplay final shot cannot show a ring, Windows would paint the focused one)
        .background { Button { focus = nil } label: { Text("x") }.buttonStyle(.plain).keyboardShortcut(.escape, modifiers: []).offset(x: 3000, y: 3000).accessibilityHidden(true) }
    }
}
