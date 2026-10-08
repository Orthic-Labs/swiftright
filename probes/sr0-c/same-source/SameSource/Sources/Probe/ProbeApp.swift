#if os(macOS)
import SwiftUI
import SharedScreens

@main
struct ProbeApp: App {
    var body: some Scene {
        Window("SR0-C Probe", id: "main") {
            makeProbeRoot()
        }
    }
}
#endif
