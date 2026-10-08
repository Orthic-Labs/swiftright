// Non-screen glue: exposes the internal screen to the Probe executable.
import SwiftRightUI
#if os(macOS)
import SwiftUI
#endif

@MainActor
public func makeProbeRoot() -> some View {
    ReorderableEditorScreen()
}
