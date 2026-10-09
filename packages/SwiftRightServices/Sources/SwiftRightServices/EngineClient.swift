import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Client for one Rust engine process speaking the RightKit framed-sidecar wire envelope.
///
/// Lifecycle: `start()` (optional; requests start the engine on demand), `request` / `call`,
/// `shutdown()`. After a crash, requests fail with `EngineError.engineExited` unless
/// `EngineConfiguration.reconnect` allows a restart. A client is single-use after `shutdown()`.
public actor EngineClient {
    /// Lifecycle and traffic events. Buffered by `maxEventBuffer` (newest kept).
    public nonisolated let events: AsyncStream<EngineEvent>

    /// Requests that received no response before their timeout and then answered anyway.
    public private(set) var lateResponseCount = 0
    /// Frames that were malformed, oversized without an id, or for an unknown request.
    public private(set) var ignoredFrameCount = 0

    private let sink: AsyncStream<EngineEvent>.Continuation
    private let configuration: EngineConfiguration

    private enum Phase: Equatable {
        case idle, starting, awaitingHello, awaitingReady, ready, stopping, crashed
    }

    private struct PendingRequest {
        let method: String
        let timeout: Duration
        let continuation: CheckedContinuation<EngineJSON, Error>
        var timer: Task<Void, Never>?
    }

    private var phase: Phase = .idle
    private var finished = false
    private var session: EngineSession?
    private var generation: UInt64 = 0
    private var decoder: EngineFrameDecoder
    private var stderrTail: [UInt8] = []
    private var hello: EngineHello?
    private var startTask: Task<EngineHello, Error>?
    private var handshakeTimer: Task<Void, Never>?
    private var handshakeWaiter: CheckedContinuation<EngineHello, Error>?
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextRequestID: UInt64 = 1
    private var pending: [UInt64: PendingRequest] = [:]
    private var outboundPending = 0
    private var restartStamps: [ContinuousClock.Instant] = []
    private var lastFailure: EngineError?

    public init(configuration: EngineConfiguration) {
        self.configuration = configuration
        let (stream, continuation) = AsyncStream<EngineEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(configuration.maxEventBuffer))
        events = stream
        sink = continuation
        decoder = EngineFrameDecoder(framing: configuration.framing, limit: configuration.maxFrameBytes)
    }

    // MARK: - Public API

    /// Starts the engine and waits for `hello` (version check) and `ready`.
    /// Returns immediately when already ready.
    public func start() async throws -> EngineHello {
        if finished { throw EngineError.notRunning }
        switch phase {
        case .ready:
            if let hello { return hello }
            throw EngineError.notRunning
        case .starting, .awaitingHello, .awaitingReady:
            guard let task = startTask else { throw EngineError.notRunning }
            return try await task.value
        case .idle, .crashed:
            return try await startSession(delay: nil).value
        case .stopping:
            throw EngineError.notRunning
        }
    }

    /// Sends one request and waits for its correlated response.
    ///
    /// Cancelling the calling task fails this call with `EngineError.cancelled`. The protocol
    /// has no cancel frame (rightkit-framed-sidecar wire.rs:58-105), so nothing is sent to the
    /// engine; a late response is counted in `lateResponseCount` and dropped.
    public func request(_ method: String, params: EngineJSON = .null, timeout: Duration? = nil) async throws -> EngineJSON {
        try await ensureReady()
        guard phase == .ready, let current = session else { throw EngineError.notRunning }
        guard pending.count < configuration.maxInFlightRequests else {
            throw EngineError.queueOverflow(limit: configuration.maxInFlightRequests, scope: .inFlightRequests)
        }
        guard outboundPending < configuration.maxOutboundFrames else {
            throw EngineError.queueOverflow(limit: configuration.maxOutboundFrames, scope: .outboundFrames)
        }
        let id = nextRequestID
        nextRequestID &+= 1
        let frame = try EngineWire.encode(
            OutboundRequest(id: id, method: method, params: params,
                            session_id: configuration.sessionID, trace_id: configuration.traceID),
            framing: configuration.framing, limit: configuration.maxFrameBytes)
        let effectiveTimeout = timeout ?? configuration.defaultRequestTimeout

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<EngineJSON, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: EngineError.cancelled(method: method, id: id))
                    return
                }
                let timer = Task {
                    do { try await Task.sleep(for: effectiveTimeout) } catch { return }
                    self.requestTimedOut(id)
                }
                self.pending[id] = PendingRequest(method: method, timeout: effectiveTimeout,
                                                  continuation: continuation, timer: timer)
                self.enqueueWrite(frame, on: current)
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    /// Stops the engine: sends `bye`, closes stdin, waits `grace`, then terminates the process.
    /// Pending requests fail with `EngineError.notRunning`. The `events` stream then finishes.
    public func shutdown(grace: Duration? = nil) async -> EngineShutdownOutcome {
        guard !finished else { return .notRunning }
        finished = true
        let grace = grace ?? configuration.shutdownGrace
        guard let current = session else {
            sink.finish()
            return .notRunning
        }
        let generation = current.generation
        phase = .stopping
        let bye = try? EngineWire.encode(OutboundBye(reason: "shutdown"),
                                         framing: configuration.framing, limit: configuration.maxFrameBytes)
        current.queue.async {
            if let bye { try? current.stdin.write(contentsOf: bye) }
            try? current.stdin.close()
        }
        var forced = false
        if await !waitForExit(generation, timeout: grace) {
            forced = true
            if current.process.isRunning { current.process.terminate() }
            _ = await waitForExit(generation, timeout: .seconds(5))
        }
        sink.finish()
        return forced ? .terminated(status: current.exit.status) : .exited(status: current.exit.status)
    }

    // MARK: - Session lifecycle

    private func startSession(delay: Duration?) -> Task<EngineHello, Error> {
        phase = .starting
        let task = Task { () throws -> EngineHello in
            if let delay { try await Task.sleep(for: delay) }
            return try await self.launch()
        }
        startTask = task
        return task
    }

    private func ensureReady() async throws {
        if finished { throw EngineError.notRunning }
        switch phase {
        case .ready:
            return
        case .starting, .awaitingHello, .awaitingReady:
            guard let task = startTask else { throw EngineError.notRunning }
            _ = try await task.value
        case .idle:
            _ = try await startSession(delay: nil).value
        case .crashed:
            let policy = configuration.reconnect
            guard policy.maxRestarts > 0, consumeRestartBudget(policy) else {
                throw lastFailure ?? EngineError.notRunning
            }
            _ = try await startSession(delay: policy.backoff).value
        case .stopping:
            throw EngineError.notRunning
        }
    }

    private func consumeRestartBudget(_ policy: ReconnectPolicy) -> Bool {
        let now = ContinuousClock.now
        restartStamps.removeAll { now - $0 > policy.window }
        guard restartStamps.count < policy.maxRestarts else { return false }
        restartStamps.append(now)
        return true
    }

    private func launch() async throws -> EngineHello {
        guard !finished, phase == .starting else { throw EngineError.notRunning }
        #if !os(Windows)
        _ = Self.sigpipeIgnored
        #endif
        generation &+= 1
        let gen = generation

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = configuration.executable
        process.arguments = configuration.arguments
        process.environment = configuration.environment
        process.currentDirectoryURL = configuration.workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            phase = .crashed
            throw EngineError.launchFailed(String(describing: error))
        }
        // Close the child's ends in the parent so EOF reaches us when the engine exits.
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let exit = EngineExitBox(process: process)
        let current = EngineSession(
            generation: gen, process: process, stdin: stdinPipe.fileHandleForWriting,
            queue: DispatchQueue(label: "swiftright.engine.stdin.\(gen)"), exit: exit)
        session = current
        decoder = EngineFrameDecoder(framing: configuration.framing, limit: configuration.maxFrameBytes)
        stderrTail = []
        hello = nil
        phase = .awaitingHello

        let (stdoutStream, stdoutContinuation) = AsyncStream<Data>.makeStream()
        let (stderrStream, stderrContinuation) = AsyncStream<Data>.makeStream()
        EnginePipes.pump(stdoutPipe.fileHandleForReading, into: stdoutContinuation) { exit.waitAndRecord() }
        EnginePipes.pump(stderrPipe.fileHandleForReading, into: stderrContinuation, onEnd: nil)
        Task { await self.consumeStdout(gen, stdoutStream) }
        Task { await self.consumeStderr(gen, stderrStream) }
        armHandshakeTimer(gen, configuration.handshakeTimeout)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<EngineHello, Error>) in
            self.handshakeWaiter = continuation
        }
    }

    #if !os(Windows)
    private static let sigpipeIgnored: Bool = {
        // A write to a dead engine's stdin must fail with an error, not kill the host process.
        _ = signal(SIGPIPE, SIG_IGN)
        return true
    }()
    #endif

    /// Ends the session identified by `gen`. Fails the handshake waiter and every pending request.
    private func teardown(_ gen: UInt64, error: EngineError?) {
        guard let current = session, current.generation == gen else { return }
        let stopping = phase == .stopping
        if error != nil, current.process.isRunning { current.process.terminate() }
        let failure: EngineError = stopping
            ? .notRunning
            : (error ?? .engineExited(status: current.exit.status, stderrTail: stderrText()))
        session = nil
        hello = nil
        handshakeTimer?.cancel()
        handshakeTimer = nil
        if let waiter = handshakeWaiter {
            handshakeWaiter = nil
            waiter.resume(throwing: failure)
        }
        for id in Array(pending.keys) {
            take(id)?.continuation.resume(throwing: failure)
        }
        if stopping {
            phase = .idle
        } else {
            phase = .crashed
            lastFailure = failure
            sink.yield(.disconnected(failure))
        }
        wakeExitWaiters()
    }

    private func consumeStdout(_ gen: UInt64, _ stream: AsyncStream<Data>) async {
        for await chunk in stream {
            guard session?.generation == gen else { return }
            do {
                for output in try decoder.feed(chunk) {
                    guard session?.generation == gen else { return }
                    handle(output, gen)
                }
            } catch let error as EngineError {
                teardown(gen, error: error)
                return
            } catch {
                teardown(gen, error: .protocolViolation(String(describing: error)))
                return
            }
        }
        // End of file: the reader thread waited for the exit status before finishing the stream.
        teardown(gen, error: nil)
    }

    private func consumeStderr(_ gen: UInt64, _ stream: AsyncStream<Data>) async {
        for await chunk in stream {
            guard session?.generation == gen else { return }
            stderrTail.append(contentsOf: chunk)
            let excess = stderrTail.count - configuration.stderrTailBytes
            if excess > 0 { stderrTail.removeFirst(excess) }
        }
    }

    private func stderrText() -> String {
        String(decoding: stderrTail, as: UTF8.self)
    }

    private func armHandshakeTimer(_ gen: UInt64, _ after: Duration) {
        handshakeTimer?.cancel()
        let armedPhase = phase
        handshakeTimer = Task {
            do { try await Task.sleep(for: after) } catch { return }
            self.handshakeTimedOut(gen, armedPhase, after)
        }
    }

    private func handshakeTimedOut(_ gen: UInt64, _ armed: Phase, _ after: Duration) {
        guard session?.generation == gen, phase == armed else { return }
        guard armed == .awaitingHello || armed == .awaitingReady else { return }
        teardown(gen, error: .handshakeTimeout(stage: armed == .awaitingHello ? "hello" : "ready", after: after))
    }

    // MARK: - Inbound frames

    private func handle(_ output: EngineFrameDecoder.Output, _ gen: UInt64) {
        switch output {
        case .oversized(let requestID, let bytes):
            if let id = requestID, pending[id] != nil {
                take(id)?.continuation.resume(throwing: EngineError.frameTooLarge(
                    limit: configuration.maxFrameBytes, requestID: id))
            } else {
                _ = bytes
                ignoredFrameCount += 1
            }
        case .body(let body):
            guard let inbound = EngineInbound.parse(body) else {
                ignoredFrameCount += 1
                return
            }
            handleInbound(inbound, gen)
        }
    }

    private func handleInbound(_ frame: EngineInbound, _ gen: UInt64) {
        if case .bye = frame { return }
        if case .ignored = frame { return }
        switch phase {
        case .awaitingHello:
            guard case .hello(let info) = frame else {
                teardown(gen, error: .handshakeFailed("expected hello as the first frame"))
                return
            }
            let range = configuration.supportedContractVersions
            guard range.contains(info.contractVersion) else {
                teardown(gen, error: .incompatibleProtocol(
                    engine: info.engine, received: info.contractVersion, supported: range))
                return
            }
            hello = info
            phase = .awaitingReady
            armHandshakeTimer(gen, configuration.readyTimeout)

        case .awaitingReady:
            switch frame {
            case .ready:
                guard let info = hello else { return }
                phase = .ready
                handshakeTimer?.cancel()
                handshakeTimer = nil
                let waiter = handshakeWaiter
                handshakeWaiter = nil
                waiter?.resume(returning: info)
                sink.yield(.connected(info))
            case .hello:
                teardown(gen, error: .handshakeFailed("duplicate hello before ready"))
            default:
                teardown(gen, error: .handshakeFailed("expected ready before requests"))
            }

        case .ready, .stopping:
            switch frame {
            case .response(let id, let ok, let result, let error):
                guard let waiting = take(id) else {
                    lateResponseCount += 1
                    return
                }
                if ok {
                    waiting.continuation.resume(returning: result ?? .null)
                } else {
                    waiting.continuation.resume(throwing: EngineError.remote(
                        code: error?.code ?? "unknown", message: error?.message ?? "",
                        retryable: error?.retryable ?? false))
                }
            case .event(let id, let sessionID, let payload):
                if let id, pending[id] != nil {
                    sink.yield(.progress(requestID: id, sessionID: sessionID, payload: payload))
                } else {
                    sink.yield(.unsolicited(sessionID: sessionID, payload: payload))
                }
            default:
                ignoredFrameCount += 1
            }

        case .idle, .starting, .crashed:
            break
        }
    }

    // MARK: - Requests

    private func take(_ id: UInt64) -> PendingRequest? {
        guard let request = pending.removeValue(forKey: id) else { return nil }
        request.timer?.cancel()
        return request
    }

    private func cancelRequest(_ id: UInt64) {
        guard let request = take(id) else { return }
        request.continuation.resume(throwing: EngineError.cancelled(method: request.method, id: id))
    }

    private func requestTimedOut(_ id: UInt64) {
        guard let request = take(id) else { return }
        request.continuation.resume(throwing: EngineError.requestTimeout(
            method: request.method, id: id, after: request.timeout))
    }

    private func enqueueWrite(_ frame: Data, on current: EngineSession) {
        outboundPending += 1
        let gen = current.generation
        current.queue.async {
            var failed = false
            do {
                try current.stdin.write(contentsOf: frame)
            } catch {
                failed = true
            }
            Task { await self.outboundWritten(gen, failed: failed) }
        }
    }

    private func outboundWritten(_ gen: UInt64, failed: Bool) {
        outboundPending = max(0, outboundPending - 1)
        if failed, session?.generation == gen {
            teardown(gen, error: .protocolViolation("stdin write failed; engine pipe is closed"))
        }
    }

    // MARK: - Shutdown helpers

    private func waitForExit(_ gen: UInt64, timeout: Duration) async -> Bool {
        guard session?.generation == gen else { return true }
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            self.wakeExitWaiters()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.exitWaiters.append(continuation)
        }
        timer.cancel()
        return session?.generation != gen
    }

    private func wakeExitWaiters() {
        let waiters = exitWaiters
        exitWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

extension EngineClient {
    /// Payload mapping: encodes `params` and decodes the result into `Response`.
    /// Non-isolated so the typed values never cross the actor boundary; only `EngineJSON` does.
    public nonisolated func call<Params: Encodable, Response: Decodable>(
        _ method: String,
        params: Params,
        as responseType: Response.Type = Response.self,
        timeout: Duration? = nil
    ) async throws -> Response {
        let payload: EngineJSON
        do {
            payload = try EngineJSON(encoding: params)
        } catch {
            throw EngineError.payloadMapping(method: method, underlying: String(describing: error))
        }
        let value = try await request(method, params: payload, timeout: timeout)
        do {
            return try value.decode(Response.self)
        } catch {
            throw EngineError.payloadMapping(method: method, underlying: String(describing: error))
        }
    }
}
