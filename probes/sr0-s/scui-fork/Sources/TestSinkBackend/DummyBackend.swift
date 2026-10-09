import Foundation
@_spi(Backends) import SwiftCrossUI

/// SR0-S commit sink: DummyBackend (upstream, MIT) recording the committed widget tree instead of
/// drawing. Additions over upstream: a manually drained main-thread queue, focus handling, a
/// fixed-advance text measurer, and a resolved-tree snapshot (see SinkTree.swift).
@MainActor
public final class DummyBackend {
    public var incomingURLHandler: ((URL) -> Void)?
    public var appPhase = AppPhase.active

    /// Work scheduled through `runInMainThread`; the test harness drains it deterministically.
    public nonisolated let mainQueue = MainQueue()
    /// Text of every `size(of:)` measurement request, in order.
    public var measureRequests: [String] = []
    /// Widget that currently holds keyboard focus.
    public weak var focusedWidget: Widget?
    /// Focus observers registered per widget (by identity).
    var focusObservers: [ObjectIdentifier: [WidgetFocusObserver]] = [:]
    /// Number of `show(widget:)`/commit-time calls, per tag, for lifecycle assertions.
    public var commitCount = 0

    public init() {}

    /// Runs queued main-thread work until none remains. Returns how many items ran.
    @discardableResult
    public func drainMain() -> Int {
        var ran = 0
        while let work = mainQueue.pop() {
            work()
            ran += 1
        }
        return ran
    }
}

public final class MainQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [@MainActor () -> Void] = []
    public init() {}
    public func push(_ work: @escaping @MainActor () -> Void) {
        lock.lock(); items.append(work); lock.unlock()
    }
    func pop() -> (@MainActor () -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return items.isEmpty ? nil : items.removeFirst()
    }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
}
