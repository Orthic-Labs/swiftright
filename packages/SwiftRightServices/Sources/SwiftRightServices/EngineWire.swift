import Foundation

/// Framing used on the engine's stdin/stdout. Both carry the same `wire` envelope.
public enum EngineFraming: Sendable, Equatable {
    /// One compact JSON object per line. Mirrors `read_json_line` / `write_json_line`
    /// (rightkit-framed-sidecar src/lib.rs:133, :317).
    case jsonLines
    /// 4-byte big-endian length, then UTF-8 JSON. Mirrors `length_prefixed` (src/length_prefixed.rs:25, :58).
    case lengthPrefixed
}

/// Identity fields of the engine's `hello` frame.
public struct EngineHello: Sendable, Equatable {
    public var engine: String
    public var version: String
    public var contractVersion: UInt32

    public init(engine: String, version: String, contractVersion: UInt32) {
        self.engine = engine
        self.version = version
        self.contractVersion = contractVersion
    }
}

/// Outbound `request` frame (wire.rs:72-81).
struct OutboundRequest: Encodable {
    let type = "request"
    let id: UInt64
    let method: String
    let params: EngineJSON
    let session_id: String?
    let trace_id: String?
}

/// Outbound `bye` frame (wire.rs:100-104).
struct OutboundBye: Encodable {
    let type = "bye"
    let reason: String
}

/// Inbound frame, parsed leniently: unknown fields are ignored, unknown `type` values are `.ignored`.
enum EngineInbound: Equatable, Sendable {
    case hello(EngineHello)
    case ready
    case response(id: UInt64, ok: Bool, result: EngineJSON?, error: WireError?)
    case event(id: UInt64?, sessionID: String?, payload: EngineJSON)
    case bye
    case ignored

    /// Returns nil for a line that is not a JSON object with a valid envelope shape.
    static func parse(_ body: Data) -> EngineInbound? {
        guard let raw = try? JSONDecoder().decode(RawFrame.self, from: body) else { return nil }
        switch raw.type {
        case "hello":
            return .hello(EngineHello(engine: raw.engine ?? "", version: raw.version ?? "",
                                      contractVersion: raw.contractVersion ?? 0))
        case "ready":
            return .ready
        case "response":
            guard let id = raw.id, let ok = raw.ok else { return nil }
            return .response(id: id, ok: ok, result: raw.result, error: raw.error)
        case "event":
            guard let payload = raw.event else { return nil }
            return .event(id: raw.id, sessionID: raw.sessionID, payload: payload)
        case "bye":
            return .bye
        default:
            return .ignored
        }
    }

    private struct RawFrame: Decodable {
        let type: String
        let engine: String?
        let version: String?
        let contractVersion: UInt32?
        let id: UInt64?
        let ok: Bool?
        let result: EngineJSON?
        let error: WireError?
        let sessionID: String?
        let event: EngineJSON?

        enum CodingKeys: String, CodingKey {
            case type, engine, version, id, ok, result, error, event
            case contractVersion = "contract_version"
            case sessionID = "session_id"
        }
    }
}

/// `response.error` as carried on the wire (wire.rs:29-36). Missing fields default like Rust.
struct WireError: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let retryable: Bool

    enum CodingKeys: String, CodingKey { case code, message, retryable }

    init(code: String, message: String, retryable: Bool) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false
    }
}

enum EngineWire {
    /// Encodes one envelope and applies the framing and size limit. Nothing is produced on failure.
    static func encode<Value: Encodable>(_ value: Value, framing: EngineFraming, limit: Int) throws -> Data {
        try frame(JSONEncoder().encode(value), framing: framing, limit: limit)
    }

    static func frame(_ body: Data, framing: EngineFraming, limit: Int) throws -> Data {
        switch framing {
        case .jsonLines:
            guard body.count <= limit else { throw EngineError.frameTooLarge(limit: limit, requestID: nil) }
            var line = body
            line.append(0x0A)
            return line
        case .lengthPrefixed:
            guard !body.isEmpty else { throw EngineError.malformedFrame("empty frame body") }
            guard body.count <= limit, body.count <= Int(UInt32.max) else {
                throw EngineError.frameTooLarge(limit: limit, requestID: nil)
            }
            var out = Data()
            out.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) })
            out.append(body)
            return out
        }
    }
}

/// Incremental decoder for one framing. Feed raw bytes in any chunking; it returns complete
/// bodies and oversized frames. Throws only for fatal framing errors (the stream cannot resync).
struct EngineFrameDecoder {
    enum Output: Equatable {
        case body(Data)
        /// An over-limit frame was drained. `requestID` is parsed from its head when present.
        case oversized(requestID: UInt64?, bytes: Int)
    }

    static let headBytes = 4096

    let framing: EngineFraming
    let limit: Int
    let maxDiscard: Int
    private var buffer: [UInt8] = []
    private var discarding = false
    private var discardedTotal = 0
    private var discardHead: [UInt8] = []
    private var discardSeen = 0

    init(framing: EngineFraming, limit: Int, maxDiscard: Int = 64 * 1024 * 1024) {
        self.framing = framing
        self.limit = limit
        self.maxDiscard = maxDiscard
    }

    mutating func feed(_ data: Data) throws -> [Output] {
        buffer.append(contentsOf: data)
        switch framing {
        case .jsonLines: return try feedJSONLines()
        case .lengthPrefixed: return try feedLengthPrefixed()
        }
    }

    // Mirrors read_json_line_or_oversized (src/lib.rs:213-311): blank lines are skipped, one
    // trailing CR is stripped, and an over-limit line is drained up to its newline.
    private mutating func feedJSONLines() throws -> [Output] {
        var outputs: [Output] = []
        var index = 0
        loop: while true {
            if discarding {
                if let newline = buffer[index...].firstIndex(of: 0x0A) {
                    let consumed = newline - index + 1
                    discardedTotal += consumed
                    discardSeen += consumed - 1
                    index = newline + 1
                    discarding = false
                    outputs.append(.oversized(requestID: Self.peekRequestID(discardHead), bytes: discardSeen))
                    discardHead = []
                } else {
                    let rest = buffer.count - index
                    discardedTotal += rest
                    discardSeen += rest
                    index = buffer.count
                    if discardedTotal > maxDiscard {
                        throw EngineError.malformedFrame("frame exceeded \(limit) bytes and no newline within \(maxDiscard) bytes")
                    }
                    break loop
                }
                continue loop
            }
            guard let newline = buffer[index...].firstIndex(of: 0x0A) else {
                let pendingCount = buffer.count - index
                if pendingCount > limit + 1 {
                    // One CR may precede the newline, so limit + 1 pending bytes is the most a valid frame can hold.
                    discarding = true
                    discardHead = Array(buffer[index..<(index + min(pendingCount, Self.headBytes))])
                    discardSeen = pendingCount
                    discardedTotal = pendingCount
                    index = buffer.count
                }
                break loop
            }
            var line = Array(buffer[index..<newline])
            index = newline + 1
            if line.last == 0x0D { line.removeLast() }
            if line.isEmpty { continue loop }
            if line.count > limit {
                outputs.append(.oversized(requestID: Self.peekRequestID(Array(line.prefix(Self.headBytes))), bytes: line.count))
            } else {
                outputs.append(.body(Data(line)))
            }
        }
        buffer.removeFirst(index)
        return outputs
    }

    // Mirrors read_frame_bytes (src/length_prefixed.rs:58-89). Over-limit and zero-length
    // prefixes are fatal because there is no resynchronisation.
    private mutating func feedLengthPrefixed() throws -> [Output] {
        var outputs: [Output] = []
        var index = 0
        while buffer.count - index >= 4 {
            let length = Int(UInt32(buffer[index]) << 24 | UInt32(buffer[index + 1]) << 16
                | UInt32(buffer[index + 2]) << 8 | UInt32(buffer[index + 3]))
            if length == 0 { throw EngineError.malformedFrame("zero-length frame") }
            if length > limit { throw EngineError.frameTooLarge(limit: limit, requestID: nil) }
            guard buffer.count - index - 4 >= length else { break }
            outputs.append(.body(Data(buffer[(index + 4)..<(index + 4 + length)])))
            index += 4 + length
        }
        buffer.removeFirst(index)
        return outputs
    }

    /// Mirrors `peek_id` (src/lib.rs:196-208): finds `"id":<digits>` in the first bytes of a frame.
    static func peekRequestID(_ head: [UInt8]) -> UInt64? {
        let key = Array("\"id\":".utf8)
        let window = head.prefix(headBytes)
        guard window.count >= key.count else { return nil }
        var start: Int?
        for i in 0...(window.count - key.count) where window[i..<(i + key.count)].elementsEqual(key) {
            start = i + key.count
            break
        }
        guard var cursor = start else { return nil }
        while cursor < window.count, window[cursor] == 0x20 || window[cursor] == 0x09 { cursor += 1 }
        var digits = ""
        while cursor < window.count, window[cursor] >= 0x30, window[cursor] <= 0x39 {
            digits.append(Character(UnicodeScalar(window[cursor])))
            cursor += 1
        }
        return UInt64(digits)
    }
}
