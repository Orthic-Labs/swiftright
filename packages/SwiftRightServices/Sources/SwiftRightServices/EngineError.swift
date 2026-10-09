import Foundation

/// Typed failures surfaced by `EngineClient`. Every failure path maps to one case.
public enum EngineError: Error, Equatable, Sendable {
    /// The child process could not be started.
    case launchFailed(String)
    /// No `hello` (stage "hello") or `ready` (stage "ready") arrived in time.
    case handshakeTimeout(stage: String, after: Duration)
    /// The engine sent frames out of handshake order or a malformed handshake.
    case handshakeFailed(String)
    /// `hello.contract_version` is outside `EngineConfiguration.supportedContractVersions`.
    case incompatibleProtocol(engine: String, received: UInt32, supported: ClosedRange<UInt32>)
    /// The client is not running (never started, shut down, or crashed without reconnect).
    case notRunning
    /// A bounded queue is full. `scope` says which bound was hit.
    case queueOverflow(limit: Int, scope: OverflowScope)
    /// No `response` for request `id` arrived within `after`.
    case requestTimeout(method: String, id: UInt64, after: Duration)
    /// The caller's task was cancelled before a response arrived.
    case cancelled(method: String, id: UInt64)
    /// The engine answered `ok: false`. `code`, `message`, `retryable` come from `response.error`.
    case remote(code: String, message: String, retryable: Bool)
    /// A frame exceeded `maxFrameBytes`. `requestID` is set when the frame named its request.
    case frameTooLarge(limit: Int, requestID: UInt64?)
    /// A frame could not be decoded or violated framing rules (zero-length prefix, etc.).
    case malformedFrame(String)
    /// The stream is unusable after a protocol violation; the engine process was stopped.
    case protocolViolation(String)
    /// The engine process ended while the client expected it to run.
    case engineExited(status: Int32?, stderrTail: String)
    /// Encoding params or decoding a result through `call` failed.
    case payloadMapping(method: String, underlying: String)
}

public enum OverflowScope: Equatable, Sendable {
    /// `maxInFlightRequests` requests are awaiting a response.
    case inFlightRequests
    /// `maxOutboundFrames` frames are queued for the engine's stdin and not yet written.
    case outboundFrames
}
