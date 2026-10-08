import Foundation
import SwiftUI

/// Owns the log, engine, model and driver for one launched fixture process.
@MainActor
public final class FixtureSession {
    public let config: FixtureConfig
    let log: EventLog
    let engine: FakeEngine
    let model: RowModel
    let driver: FixtureDriver
    private var attached = false

    public init(config: FixtureConfig) {
        self.config = config
        let log = EventLog(fixture: config.fixture.rawValue, path: config.eventsPath)
        let engine = FakeEngine(log: log)
        let model = RowModel(
            fixtureNumber: config.fixture.number,
            log: log,
            engine: engine,
            reducedMotion: config.reducedMotion
        )
        self.log = log
        self.engine = engine
        self.model = model
        self.driver = FixtureDriver(model: model, engine: engine, log: log)
    }

    /// Starts either the scripted self-test or the stdin JSON-lines driver, exactly once.
    func attach() {
        guard !attached else { return }
        attached = true
        if config.selfTest {
            SelfTestRunner(session: self).start()
        } else {
            startStdinDriver()
        }
    }

    private func startStdinDriver() {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        Thread.detachNewThread {
            while let line = readLine() {
                continuation.yield(line)
            }
            continuation.finish()
        }
        let driver = self.driver
        Task {
            for await line in stream {
                await driver.handleLine(line)
            }
        }
    }
}

public struct FixtureRootView: View {
    let session: FixtureSession

    public init(session: FixtureSession) {
        self.session = session
    }

    public var body: some View {
        screen
            .onAppear { session.attach() }
    }

    @ViewBuilder
    private var screen: some View {
        switch session.config.fixture {
        case .F1: F1Screen(model: session.model)
        case .F2: F2Screen(model: session.model)
        case .F3: F3Screen(model: session.model)
        case .F4: F4Screen(model: session.model)
        case .F5: F5Screen(model: session.model)
        case .F6: F6Screen(model: session.model)
        case .F7: F7Screen(model: session.model)
        case .F8: F8Screen(model: session.model)
        case .F9: F9Screen(model: session.model)
        }
    }
}
