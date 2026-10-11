import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// `task(id:)`: cancels and restarts when the id changes, starts on appear, cancels on disappear.
// Mac oracle context: the F8 toolbar restart case was blocked on the Windows side for lack of task(id:).

/// Event and result log shared by a test and its views.
@MainActor
final class KeyLog {
    var events: [String] = []
    var results: [String] = []

    func waitForTerminalCommit(timeout: Duration = .milliseconds(500)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !events.contains(where: { $0.hasPrefix("commit=") }) {
            if clock.now >= deadline { return false }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}

/// Task body for one id. It sleeps, then commits through the owner token. A cancelled run still commits
/// through the guarded path, so a stale run is rejected by the token and not by its own cancellation.
@MainActor
struct KeyedWork {
    let key: String
    let log: KeyLog

    func run() async {
        log.events.append("start \(key)")
        do {
            try await Task.sleep(for: .milliseconds(40))
        } catch {
            log.events.append("cancelled \(key)")
        }
        let accepted = TaskOwner.current?.commit { log.results.append(key) } ?? false
        log.events.append("commit=\(accepted) \(key)")
    }
}

@Observable
@MainActor
final class KeyModel {
    var key = "a"
    var other = 0
    var visible = true
}

struct KeyTaskScreen: View {
    @Bindable var model: KeyModel
    let log: KeyLog

    var body: some View {
        VStack {
            if model.visible {
                let key = model.key
                Text("key \(key) \(model.other)")
                    .task(id: key) { await KeyedWork(key: key, log: log).run() }
                    .onDisappear { log.events.append("disappear \(key)") }
            }
        }
    }
}

@MainActor
final class TaskIDTests: XCTestCase {

    // Changing the id cancels the old run (still sleeping), starts a new one, and rejects the old run's
    // commit. Only the live run commits.
    func testIdChangeCancelsAndRestartsTask() async throws {
        let model = KeyModel()
        let log = KeyLog()
        let graph = Graph(KeyTaskScreen(model: model, log: log))
        graph.flush()

        model.key = "b"
        graph.flush()
        try await settle()
        XCTAssertTrue(log.events.contains("cancelled a"), "old run cancelled on id change")
        XCTAssertTrue(log.events.contains("start b"), "new run started")
        XCTAssertTrue(log.events.contains("commit=false a"), "old run's commit rejected")
        XCTAssertTrue(log.events.contains("commit=true b"), "live run commits")
        XCTAssertEqual(log.results, ["b"], "only the live run commits")
    }

    // Re-evaluation with the same id does not restart the task.
    func testSameIdDoesNotRestartTask() async throws {
        let model = KeyModel()
        let log = KeyLog()
        let graph = Graph(KeyTaskScreen(model: model, log: log))
        graph.flush()

        model.other += 1
        graph.flush()
        let retainedGraph = graph
        let terminal = await log.waitForTerminalCommit()
        _ = retainedGraph.snapshot()
        try await settle()
        print("DIAG variant=terminal terminal=\(terminal) events=\(log.events) results=\(log.results)")
        XCTAssertEqual(log.events.filter { $0 == "start a" }.count, 1, "no restart for an unchanged id")
        XCTAssertEqual(log.results, ["a"])
    }

    // Disappearing cancels the task, and its commit is rejected.
    func testDisappearCancelsTask() async throws {
        let model = KeyModel()
        let log = KeyLog()
        let graph = Graph(KeyTaskScreen(model: model, log: log))
        graph.flush()

        model.visible = false
        graph.flush()
        try await settle()
        XCTAssertTrue(log.events.contains("cancelled a"))
        XCTAssertTrue(log.events.contains("commit=false a"))
        XCTAssertTrue(log.events.contains("disappear a"))
        XCTAssertEqual(log.results, [])
    }
}
