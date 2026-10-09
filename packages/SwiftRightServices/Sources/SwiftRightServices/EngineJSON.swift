import Foundation

/// A JSON value that is `Sendable` and `Equatable`, used for request params, results and
/// event payloads. Integers and doubles stay distinct so 64-bit ids round-trip exactly.
///
/// Bulk binary data must not be sent through this type: `Data` fields encode as base64 under
/// `JSONEncoder`, and the wire protocol has no binary payload type (see README.md).
public enum EngineJSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([EngineJSON])
    case object([String: EngineJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EngineJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: EngineJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Payload mapping: encode any `Encodable` into an `EngineJSON` value.
    public init<Value: Encodable>(encoding value: Value) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(EngineJSON.self, from: data)
    }

    /// Payload mapping: decode this value into any `Decodable` type.
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
