import Foundation

/// SR0-O trace schema v0. Field meanings follow architecture §11 and CONTRACT.md §3/§5.
/// Values are normalized before comparison; timestamps are recorded but never compared.
public let traceSchemaVersion = "sr0-o.trace/v0"

public struct PlatformTuple: Codable, Sendable, Equatable {
    public var os: String          // "macos" | "windows"
    public var osBuild: String
    public var arch: String
    public var toolchain: String
}

public struct TraceStep: Codable, Sendable, Equatable {
    public var id: String
    public var logicalAction: String   // platform-neutral intent
    public var nativeMapping: String   // platform-specific input, from CONTRACT §4
    public var timestamp: String       // recorded only; never compared
}

public struct UTF16Range: Codable, Sendable, Equatable {
    public var location: Int
    public var length: Int
}

/// Lifecycle event keyed by kind and row node (`row/<uuid>`).
/// kind: appear | disappear | taskStart | taskCancel | taskComplete
public struct LifecycleEvent: Codable, Sendable, Equatable, Hashable {
    public var kind: String
    public var node: String

    var key: String { "\(kind):\(node)" }
}

/// Canonical accessibility node. Frames are intentionally absent (no geometry in SR0-O v0).
public struct CanonicalNode: Codable, Sendable, Equatable {
    public var id: String
    public var role: String
    public var label: String?
    public var value: String?
    public var actions: [String]   // canonical action names, sorted, unique
    public var parent: String?
    public var order: Int          // index among kept siblings
}

public struct Observation: Codable, Sendable, Equatable {
    public var stepId: String
    public var model: [String: String]     // row key `row/<uuid>` -> text
    public var focusedNodeId: String?      // e.g. `row/<uuid>/field`
    public var selection: UTF16Range?
    public var lifecycle: [LifecycleEvent]
    public var effects: [String]           // committed effects, ordered
    public var axNodes: [CanonicalNode]?   // nil = not captured at this step
}

/// Declared partial order: `before` must precede `after` in any candidate where both occur.
/// Keys are `kind:node`. Every other lifecycle event may permute.
public struct OrderEdge: Codable, Sendable, Equatable {
    public var before: String
    public var after: String
}

public struct Trace: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var fixtureId: String
    public var sourceHash: String
    public var platform: PlatformTuple
    public var steps: [TraceStep]
    public var observations: [Observation]
    public var declaredOrder: [OrderEdge]
    /// Conditions the run was made under (for example `reduceMotion.effective`). Compared exactly and never adaptable:
    /// two traces recorded under different conditions are not comparable, so a difference is a failure of its own.
    /// Absent (nil) when the fixture records none.
    public var conditions: [String: String]?
}

public enum TraceCodec {
    public static func decode(_ data: Data) throws -> Trace {
        try JSONDecoder().decode(Trace.self, from: data)
    }

    public static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
