import XCTest
@testable import SwiftRightServices

/// Process-level tests: each drives EngineClient against the FakeEngine child process.
final class EngineClientTests: XCTestCase {
    private func configuration(_ extra: [String] = [], _ tweak: (inout EngineConfiguration) -> Void = { _ in }) throws -> EngineConfiguration {
        var config = EngineConfiguration(executable: try FakeEngineLocator.url(), arguments: extra)
        config.handshakeTimeout = .seconds(5)
        config.readyTimeout = .seconds(5)
        config.defaultRequestTimeout = .seconds(5)
        config.shutdownGrace = .seconds(3)
        tweak(&config)
        return config
    }

    /// Runs `body` and always shuts the engine down, even when the body throws.
    private func withClient<T>(_ config: EngineConfiguration, _ body: (EngineClient) async throws -> T) async throws -> T {
        let client = EngineClient(configuration: config)
        do {
            let value = try await body(client)
            _ = await client.shutdown()
            return value
        } catch {
            _ = await client.shutdown()
            throw error
        }
    }

    private func expectError(_ expected: EngineError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> some Any) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as EngineError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected EngineError, got \(error)", file: file, line: line)
        }
    }

    // MARK: - Handshake

    func testHandshakeAndEchoOverJSONLines() async throws {
        try await withClient(configuration()) { client in
            let hello = try await client.start()
            XCTAssertEqual(hello, EngineHello(engine: "fake", version: "0.1.0", contractVersion: 1))
            let echoed = try await client.request("echo", params: .object(["x": .integer(7)]))
            XCTAssertEqual(echoed, .object(["x": .integer(7)]))
        }
    }

    func testHandshakeAndEchoOverLengthPrefixed() async throws {
        let config = try configuration(["--framing", "lp"]) { $0.framing = .lengthPrefixed }
        try await withClient(config) { client in
            _ = try await client.start()
            let echoed = try await client.request("echo", params: .string("line\nbreak"))
            XCTAssertEqual(echoed, .string("line\nbreak"))
        }
    }

    func testVersionMismatchIsRejectedWithTypedError() async throws {
        let config = try configuration(["--contract", "9"])
        let client = EngineClient(configuration: config)
        await expectError(.incompatibleProtocol(engine: "fake", received: 9, supported: 1...1)) {
            try await client.start()
        }
        let outcome = await client.shutdown()
        XCTAssertEqual(outcome, .notRunning)
    }

    func testSilentEngineHitsHandshakeTimeout() async throws {
        let config = try configuration(["--silent"]) { $0.handshakeTimeout = .milliseconds(400) }
        let client = EngineClient(configuration: config)
        await expectError(.handshakeTimeout(stage: "hello", after: .milliseconds(400))) {
            try await client.start()
        }
        _ = await client.shutdown()
    }

    // MARK: - Correlation, timeout, cancellation, bounds

    func testConcurrentRequestsCorrelateOutOfOrderResponses() async throws {
        try await withClient(configuration()) { client in
            let results = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                for index in 0..<40 {
                    group.addTask {
                        let ms = (index * 37) % 180
                        let reply = try await client.request("sleep", params: .object([
                            "ms": .integer(Int64(ms)), "value": .integer(Int64(index))]))
                        guard case .object(let fields) = reply, case .integer(let value)? = fields["value"] else {
                            throw EngineError.payloadMapping(method: "sleep", underlying: "shape")
                        }
                        return (index, Int(value))
                    }
                }
                var collected: [Int: Int] = [:]
                for try await (index, value) in group { collected[index] = value }
                return collected
            }
            XCTAssertEqual(results.count, 40)
            for index in 0..<40 {
                XCTAssertEqual(results[index], index, "response for request \(index) was mis-correlated")
            }
        }
    }

    func testTimeoutFailsRequestAndLateResponseIsDropped() async throws {
        try await withClient(configuration()) { client in
            await expectError(.requestTimeout(method: "sleep", id: 1, after: .milliseconds(150))) {
                try await client.request("sleep", params: .object(["ms": .integer(900), "value": .integer(1)]),
                                         timeout: .milliseconds(150))
            }
            let next = try await client.request("echo", params: .integer(2))
            XCTAssertEqual(next, .integer(2))
            try await Task.sleep(for: .milliseconds(1200))
            let late = await client.lateResponseCount
            XCTAssertEqual(late, 1)
        }
    }

    func testCancellingCallerFailsWithCancelled() async throws {
        try await withClient(configuration()) { client in
            let task = Task { try await client.request("hang") }
            try await Task.sleep(for: .milliseconds(150))
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("expected cancellation")
            } catch let error as EngineError {
                XCTAssertEqual(error, .cancelled(method: "hang", id: 1))
            }
            // The engine is still healthy after the cancelled request.
            let next = try await client.request("echo", params: .string("alive"))
            XCTAssertEqual(next, .string("alive"))
        }
    }

    func testInFlightBoundOverflowIsTypedAndDoesNotKillEngine() async throws {
        let config = try configuration { $0.maxInFlightRequests = 2; $0.defaultRequestTimeout = .seconds(20) }
        let client = EngineClient(configuration: config)
        _ = try await client.start()
        let first = Task { try await client.request("hang") }
        let second = Task { try await client.request("hang") }
        try await Task.sleep(for: .milliseconds(150))
        await expectError(.queueOverflow(limit: 2, scope: .inFlightRequests)) {
            try await client.request("echo")
        }
        _ = await client.shutdown()
        // Requests still in flight at shutdown fail with notRunning, not a hang.
        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("expected notRunning")
            } catch let error as EngineError {
                XCTAssertEqual(error, .notRunning)
            }
        }
    }

    // MARK: - Typed remote errors, events, frame limits

    func testRemoteErrorIsTyped() async throws {
        try await withClient(configuration()) { client in
            await expectError(.remote(code: "bad_input", message: "nope", retryable: true)) {
                try await client.request("error")
            }
        }
    }

    func testProgressAndUnsolicitedEventsReachEventStream() async throws {
        try await withClient(configuration()) { client in
            let collected = Task { () -> [EngineEvent] in
                var seen: [EngineEvent] = []
                for await event in client.events {
                    seen.append(event)
                    if seen.count == 3 { break }
                }
                return seen
            }
            _ = try await client.request("emit")
            let seen = await collected.value
            XCTAssertEqual(seen, [
                .connected(EngineHello(engine: "fake", version: "0.1.0", contractVersion: 1)),
                .progress(requestID: 1, sessionID: nil, payload: .object(["step": .integer(1)])),
                .unsolicited(sessionID: "s1", payload: .object(["note": .string("hi")])),
            ])
        }
    }

    func testOversizedResponseFailsOnlyItsRequest() async throws {
        let config = try configuration { $0.maxFrameBytes = 4096 }
        try await withClient(config) { client in
            await expectError(.frameTooLarge(limit: 4096, requestID: 1)) {
                try await client.request("big", params: .object(["bytes": .integer(10_000)]))
            }
            let next = try await client.request("echo", params: .integer(3))
            XCTAssertEqual(next, .integer(3))
        }
    }

    // MARK: - Crash, reconnect, shutdown

    func testEngineCrashMidRequestIsTypedError() async throws {
        let client = EngineClient(configuration: try configuration())
        await expectError(.engineExited(status: 3, stderrTail: "")) {
            try await client.request("crash")
        }
        _ = await client.shutdown()
    }

    func testReconnectAfterCrashRestartsEngine() async throws {
        let config = try configuration {
            $0.reconnect = ReconnectPolicy(maxRestarts: 2, window: .seconds(60), backoff: .milliseconds(50))
        }
        let client = EngineClient(configuration: config)
        await expectError(.engineExited(status: 3, stderrTail: "")) {
            try await client.request("crash")
        }
        let recovered = try await client.request("echo", params: .string("again"))
        XCTAssertEqual(recovered, .string("again"))
        _ = await client.shutdown()
    }

    func testCrashWithoutReconnectKeepsReturningCrashError() async throws {
        let client = EngineClient(configuration: try configuration())
        await expectError(.engineExited(status: 3, stderrTail: "")) { try await client.request("crash") }
        await expectError(.engineExited(status: 3, stderrTail: "")) { try await client.request("echo") }
        _ = await client.shutdown()
    }

    func testGracefulShutdownExitsAndRejectsLaterRequests() async throws {
        let client = EngineClient(configuration: try configuration())
        _ = try await client.start()
        let outcome = await client.shutdown()
        XCTAssertEqual(outcome, .exited(status: 0))
        await expectError(.notRunning) { try await client.request("echo") }
    }

    func testStubbornEngineIsTerminatedAfterGrace() async throws {
        let config = try configuration(["--stubborn"])
        let client = EngineClient(configuration: config)
        _ = try await client.start()
        let outcome = await client.shutdown(grace: .milliseconds(300))
        guard case .terminated = outcome else { return XCTFail("expected terminated, got \(outcome)") }
    }

    func testRequestBeforeStartAutoStarts() async throws {
        let client = EngineClient(configuration: try configuration())
        let value = try await client.request("echo", params: .bool(true))
        XCTAssertEqual(value, .bool(true))
        _ = await client.shutdown()
    }

    func testTypedCallRoundTripsThroughEngine() async throws {
        struct Payload: Codable, Equatable { var name: String; var count: Int }
        try await withClient(configuration()) { client in
            let reply: Payload = try await client.call("echo", params: Payload(name: "a", count: 2))
            XCTAssertEqual(reply, Payload(name: "a", count: 2))
        }
    }
}
