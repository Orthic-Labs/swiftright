import Foundation
import Observation
import TestSinkBackend
import XCTest

@testable @_spi(Backends) import SwiftCrossUI

/// Drives a root view through SCUI's real `WindowReference` (the production root driver) on the
/// commit-sink backend. `flush()` replaces the fresh runtime's `Graph.flush()`: SCUI schedules
/// updates through `Publisher.observeAsUIUpdater` (hop to a serial dispatch queue, then
/// `backend.runInMainThread`), so a flush has to drain until the system is quiet.
@MainActor
final class Harness<Root: View> {
    let backend = DummyBackend()
    let reference: WindowReference<Window<Root>>
    let scene: Window<Root>
    let environment: EnvironmentValues
    var window: DummyBackend.Window { reference.window as! DummyBackend.Window }

    init(width: Int = 900, height: Int = 450, _ make: @escaping @MainActor () -> Root) {
        let backend = self.backend
        var env = backend.computeRootEnvironment(defaultEnvironment: EnvironmentValues(backend: backend))
        env.defaultWindowSize = SIMD2(width, height)
        env.layoutSpacing = 8
        environment = env
        scene = Window("test", id: "w", make)
        reference = WindowReference(
            scene: scene,
            backend: backend,
            environment: env,
            onClose: {},
            id: "w"
        )
        reference.update(scene, backend: backend, environment: env)
    }

    /// Drains pending main-thread work until two consecutive quiet intervals.
    func flush(_ label: String = "") async {
        var quiet = 0
        var rounds = 0
        var total = 0
        defer { if ProcessInfo.processInfo.environment["SCUI_TRACE_FLUSH"] != nil { print("FLUSH \(label) rounds=\(rounds) drained=\(total)") } }
        while quiet < 2 && rounds < 200 {
            rounds += 1
            let n = backend.drainMain()
            total += n
            if n == 0 {
                quiet += 1
                try? await Task.sleep(nanoseconds: 8_000_000)
            } else {
                quiet = 0
            }
        }
    }

    /// Drains only what is already queued (no waiting).
    @discardableResult
    func drainNow() -> Int { backend.drainMain() }

    var tree: SinkNode { backend.tree(of: window)! }

    func resize(width: Int, height: Int = 450) {
        window.size = SIMD2(width, height)
        window.resizeHandler?(window.size)
    }

    func tap(_ button: SinkNode) {
        (button.widget as! DummyBackend.Button).action?()
    }
}

@MainActor
func settle() async throws {
    for _ in 0..<3 { await Task.yield() }
    try await Task.sleep(for: .milliseconds(300))
}
