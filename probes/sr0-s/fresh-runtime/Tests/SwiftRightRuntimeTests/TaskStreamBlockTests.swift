import Foundation
import SwiftRightRuntime
import XCTest

// SR1 round 4, block swiftui.task-asyncstream: `.task { for await v in stream { ... } }` driving state. The facts below were measured on macOS 27 SwiftUI with the case
// witnesses in factory/pipeline/blocks-21-23/swiftui.task-asyncstream (events pumped by a Button, never by a timer) and are pinned here against the runtime:
// - state written by the task redraws (the write reaches the view); events arrive in the order they were yielded, also when several are yielded at once;
// - a cancelled task (its view disappeared, or its `task(id:)` changed) ends its `for await`; an event sent afterwards does not apply; the statement after the loop still runs;
// - a finished stream ends the loop and the code after it runs.

@Observable
@MainActor
final class StreamModel {
    var value = 0
    var log: [Int] = []
    var phase = "idle"
    var shown = true
    var gen = 0
    var started = "0"
}

@MainActor
final class StreamFeed {
    let pair = AsyncStream<Int>.makeStream()
    var perGen: [Int: (stream: AsyncStream<Int>, continuation: AsyncStream<Int>.Continuation)] = [:]
    func stream(_ gen: Int) -> AsyncStream<Int> {
        if let existing = perGen[gen] { return existing.stream }
        let made = AsyncStream<Int>.makeStream()
        perGen[gen] = made
        return made.stream
    }
}

private struct DrivesState: View {
    let model: StreamModel
    let feed: StreamFeed
    var body: some View {
        Text("value=\(model.value) log=\(model.log.map { String($0) }.joined(separator: ",")) phase=\(model.phase)")
            .task {
                model.phase = "running"
                for await v in feed.pair.stream { model.value = v; model.log.append(v) }
                model.phase = "done"
            }
    }
}

private struct Listener: View {
    let model: StreamModel
    let feed: StreamFeed
    var body: some View {
        Text("listener").task {
            for await v in feed.pair.stream { model.value = v }
            model.phase = "ended"
        }
    }
}

private struct CancelHost: View {
    let model: StreamModel
    let feed: StreamFeed
    var body: some View {
        VStack {
            if model.shown { Listener(model: model, feed: feed) }
            Text("value=\(model.value) phase=\(model.phase) shown=\(model.shown ? 1 : 0)")
        }
    }
}

private struct RestartHost: View {
    let model: StreamModel
    let feed: StreamFeed
    var body: some View {
        Text("gen=\(model.gen) value=\(model.value) started=\(model.started)")
            .task(id: model.gen) {
                if model.gen > 0 { model.started += "," + String(model.gen) }
                for await v in feed.stream(model.gen) { model.value = v }
            }
    }
}

@MainActor
private func texts(_ graph: Graph) -> [String] {
    everyNode(graph.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text)
}

@MainActor
final class TaskStreamBlockTests: XCTestCase {
    private func make<V: View>(_ view: V) -> Graph {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        return graph
    }

    func testStreamDrivesStateInOrderAndTheTaskStartsOnAppear() async throws {
        let model = StreamModel(), feed = StreamFeed()
        let graph = make(DrivesState(model: model, feed: feed))
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=0 log= phase=running"])
        for v in [3, 1, 2] { feed.pair.continuation.yield(v) }
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=2 log=3,1,2 phase=running"], "a burst arrives in order and the write redraws")
        feed.pair.continuation.yield(3)
        try await settle(); graph.flush()
        XCTAssertEqual(model.log, [3, 1, 2, 3])
    }

    func testFinishingTheStreamEndsTheLoopAndLaterEventsDoNothing() async throws {
        let model = StreamModel(), feed = StreamFeed()
        let graph = make(DrivesState(model: model, feed: feed))
        try await settle()
        feed.pair.continuation.yield(3)
        try await settle()
        feed.pair.continuation.finish()
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=3 log=3 phase=done"])
        feed.pair.continuation.yield(1)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=3 log=3 phase=done"])
    }

    func testCancelledTaskAppliesNoLateEventButItsCodeAfterTheLoopRuns() async throws {
        let model = StreamModel(), feed = StreamFeed()
        model.phase = "listening"
        let graph = make(CancelHost(model: model, feed: feed))
        try await settle()
        feed.pair.continuation.yield(3)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph).last, "value=3 phase=listening shown=1")
        model.shown = false
        graph.flush()
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=3 phase=ended shown=0"], "the loop ended on cancellation and the statement after it ran")
        feed.pair.continuation.yield(1)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["value=3 phase=ended shown=0"], "a late event does not apply")
    }

    func testTaskIDRestartListensToTheNewStreamAndIgnoresTheOldOne() async throws {
        let model = StreamModel(), feed = StreamFeed()
        let graph = make(RestartHost(model: model, feed: feed))
        try await settle()
        feed.perGen[0]?.continuation.yield(1)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["gen=0 value=1 started=0"])
        model.gen = 1
        graph.flush()
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["gen=1 value=1 started=0,1"])
        feed.perGen[0]?.continuation.yield(9)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["gen=1 value=1 started=0,1"], "the old run's stream is no longer listened to")
        feed.perGen[1]?.continuation.yield(3)
        try await settle(); graph.flush()
        XCTAssertEqual(texts(graph), ["gen=1 value=3 started=0,1"])
    }
}
