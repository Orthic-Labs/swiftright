import XCTest
@testable import SwiftRightServices

/// Opt-in check against a REAL Rust engine built from RightKit (rightkit-jobs example
/// `engine_fixture`, which speaks the rightkit-framed-sidecar envelope over stdio).
///
/// Skipped unless `SWR_REAL_ENGINE` holds the path of the built binary. Each test gets its own
/// `FX_DIR` state directory under the system temporary directory.
final class RealEngineTests: XCTestCase {
    private func realEngineURL() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["SWR_REAL_ENGINE"], !path.isEmpty else {
            throw XCTSkip("set SWR_REAL_ENGINE to the built engine_fixture binary to run this check")
        }
        return URL(fileURLWithPath: path)
    }

    private func configuration(requireReady: Bool) throws -> EngineConfiguration {
        let state = FileManager.default.temporaryDirectory
            .appendingPathComponent("swr-real-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        var config = EngineConfiguration(executable: try realEngineURL())
        var environment = ProcessInfo.processInfo.environment
        environment["FX_DIR"] = state.path
        environment["FX_PLAN"] = "ok"
        config.environment = environment
        config.handshakeTimeout = .seconds(5)
        config.readyTimeout = .seconds(2)
        config.defaultRequestTimeout = .seconds(5)
        config.shutdownGrace = .seconds(3)
        config.requireReady = requireReady
        return config
    }

    /// The strict default (hello, then ready) against the shipped Rust engine. The engine never
    /// sends `ready`, so the client must fail with a typed ready-stage timeout, not hang.
    func testStrictHandshakeTimesOutWaitingForReadyFromRealEngine() async throws {
        let config = try configuration(requireReady: true)
        let client = EngineClient(configuration: config)
        do {
            _ = try await client.start()
            XCTFail("strict handshake must not complete: the real engine never sends ready")
        } catch let error as EngineError {
            XCTAssertEqual(error, .handshakeTimeout(stage: "ready", after: .seconds(2)))
        } catch {
            XCTFail("expected EngineError, got \(error)")
        }
        _ = await client.shutdown()
    }

    /// Full round trip against the real engine with `requireReady = false`: handshake, success
    /// responses (including a nested payload), a typed remote error, then orderly shutdown.
    func testHandshakeRequestsErrorAndShutdownAgainstRealEngine() async throws {
        let client = EngineClient(configuration: try configuration(requireReady: false))
        do {
            let hello = try await client.start()
            XCTAssertEqual(hello, EngineHello(engine: "fixture", version: "1.0", contractVersion: 1))

            let ping = try await client.request("ping")
            XCTAssertEqual(ping, .object(["pong": .bool(true)]))

            let payload: EngineJSON = .object([
                "x": .integer(7),
                "text": .string("line\nbreak \"quoted\""),
                "nested": .array([.bool(false), .number(1.5), .null]),
            ])
            let echoed = try await client.request("echo", params: payload)
            XCTAssertEqual(echoed, payload)

            do {
                _ = try await client.request("no_such_method")
                XCTFail("unknown method must fail with a remote error")
            } catch let error as EngineError {
                XCTAssertEqual(error, .remote(code: "unknown_method", message: "no_such_method", retryable: false))
            }

            // Still usable after a remote error: the error is per request, not per session.
            let again = try await client.request("ping")
            XCTAssertEqual(again, .object(["pong": .bool(true)]))

            let outcome = await client.shutdown()
            XCTAssertEqual(outcome, .exited(status: 0))
        } catch {
            _ = await client.shutdown()
            throw error
        }
    }
}
