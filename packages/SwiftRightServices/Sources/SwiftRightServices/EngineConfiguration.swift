import Foundation

/// Restart policy after an engine crash. Restarts happen lazily on the next request.
public struct ReconnectPolicy: Sendable, Equatable {
    /// At most this many automatic restarts inside `window`.
    public var maxRestarts: Int
    public var window: Duration
    /// Delay before each automatic restart.
    public var backoff: Duration

    public init(maxRestarts: Int, window: Duration, backoff: Duration) {
        self.maxRestarts = maxRestarts
        self.window = window
        self.backoff = backoff
    }

    /// No automatic restart: after a crash, requests fail with the crash error.
    public static let disabled = ReconnectPolicy(maxRestarts: 0, window: .zero, backoff: .zero)
}

public struct EngineConfiguration: Sendable {
    public var executable: URL
    public var arguments: [String]
    /// nil inherits the parent environment.
    public var environment: [String: String]?
    public var workingDirectory: URL?
    public var framing: EngineFraming
    /// Accepted `hello.contract_version` values. Outside this range the client rejects the engine.
    public var supportedContractVersions: ClosedRange<UInt32>
    /// Limit for one frame in either direction (body bytes, excluding the newline).
    public var maxFrameBytes: Int
    /// Requests awaiting a response. Exceeding it throws `EngineError.queueOverflow`.
    public var maxInFlightRequests: Int
    /// Frames enqueued for stdin and not yet written. Exceeding it throws `EngineError.queueOverflow`.
    public var maxOutboundFrames: Int
    /// Newest events kept when the consumer of `EngineClient.events` is slow. Older events are dropped.
    public var maxEventBuffer: Int
    public var handshakeTimeout: Duration
    public var readyTimeout: Duration
    public var defaultRequestTimeout: Duration
    public var shutdownGrace: Duration
    public var reconnect: ReconnectPolicy
    /// Bytes of engine stderr kept for crash reports.
    public var stderrTailBytes: Int
    /// Optional correlation fields copied onto every request frame.
    public var sessionID: String?
    public var traceID: String?

    public init(executable: URL, arguments: [String] = [], supportedContractVersions: ClosedRange<UInt32> = 1...1) {
        self.executable = executable
        self.arguments = arguments
        self.environment = nil
        self.workingDirectory = nil
        self.framing = .jsonLines
        self.supportedContractVersions = supportedContractVersions
        self.maxFrameBytes = 16 * 1024 * 1024
        self.maxInFlightRequests = 64
        self.maxOutboundFrames = 256
        self.maxEventBuffer = 1024
        self.handshakeTimeout = .seconds(10)
        self.readyTimeout = .seconds(60)
        self.defaultRequestTimeout = .seconds(30)
        self.shutdownGrace = .seconds(5)
        self.reconnect = .disabled
        self.stderrTailBytes = 8192
        self.sessionID = nil
        self.traceID = nil
    }
}

/// Lifecycle and traffic events from `EngineClient.events`.
public enum EngineEvent: Sendable, Equatable {
    /// Handshake finished; the engine is ready for requests. Emitted again after each restart.
    case connected(EngineHello)
    /// An event that carries the id of a request in flight (progress).
    case progress(requestID: UInt64, sessionID: String?, payload: EngineJSON)
    /// An event with no request id (unsolicited).
    case unsolicited(sessionID: String?, payload: EngineJSON)
    /// The engine ended or broke the protocol. In-flight requests already failed with this error.
    case disconnected(EngineError)
}

public enum EngineShutdownOutcome: Sendable, Equatable {
    /// The engine exited after `bye` and closed stdin, within the grace period.
    case exited(status: Int32?)
    /// The engine did not exit within the grace period and was terminated.
    case terminated(status: Int32?)
    /// The client was never started or was already shut down.
    case notRunning
}
