@_spi(Backends) import SwiftCrossUI
import Foundation

extension DummyBackend: BackendFeatures.Core {
    public var deviceClass: DeviceClass { DeviceClass.desktop }

    public func runMainLoop(_ callback: @escaping @MainActor () -> Void) {
        callback()
    }

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        // SR0-S sink: queue instead of dispatching, so tests drain deterministically.
        mainQueue.push(action)
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        defaultEnvironment
            .with(\.appPhase, appPhase)
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {}
}
