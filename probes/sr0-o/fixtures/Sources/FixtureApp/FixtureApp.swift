import AppKit
import SliceFixtures
import SwiftUI

/// Self-test mode keeps the process alive after the last window closes, so F9 can capture
/// teardown events and print its verdict. Interactive mode keeps the default termination.
@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.contains("--self-test")
    }
}

@main
struct FixtureApp: App {
    @NSApplicationDelegateAdaptor(FixtureAppDelegate.self) private var delegate
    @State private var session: FixtureSession

    init() {
        let config = FixtureConfig.parse(CommandLine.arguments)
        if config.selfTest {
            // AppKit restores the last window frame from this app's defaults, which made the
            // initial width differ between runs. Self-test starts from the declared default size.
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame ") {
                defaults.removeObject(forKey: key)
            }
        }
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
