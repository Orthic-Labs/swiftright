import AppKit
import SliceFixtures
import SwiftUI

@main
struct FixtureApp: App {
    @State private var session: FixtureSession

    init() {
        let config = FixtureConfig.parse(CommandLine.arguments)
        _session = State(initialValue: FixtureSession(config: config))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("SR0 Fixture \(session.config.fixture.rawValue)", id: "main") {
            FixtureRootView(session: session)
        }
        .defaultSize(width: 480, height: 560)
    }
}
