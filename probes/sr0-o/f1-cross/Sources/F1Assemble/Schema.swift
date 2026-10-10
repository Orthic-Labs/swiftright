import Foundation

// Codable mirrors of TraceKit schema "sr0-o.trace/v0" (TraceKit has no public memberwise inits; the comparator is not edited).
// Every output is decoded by TraceKit's own types in `sr0o-trace compare`, which is the compatibility proof.
struct TPlatform: Codable { var os: String, osBuild: String, arch: String, toolchain: String }
struct TStep: Codable { var id: String, logicalAction: String, nativeMapping: String, timestamp: String }
struct TRange: Codable, Equatable { var location: Int, length: Int }
struct TLifecycle: Codable { var kind: String, node: String }
struct TNode: Codable {
    var id: String, role: String
    var label: String?, value: String?
    var actions: [String]
    var parent: String?
    var order: Int
}
struct TObservation: Codable {
    var stepId: String
    var model: [String: String]
    var focusedNodeId: String?
    var selection: TRange?
    var lifecycle: [TLifecycle]
    var effects: [String]
    var axNodes: [TNode]?
}
struct TEdge: Codable { var before: String, after: String }
struct TTrace: Codable {
    var schemaVersion = "sr0-o.trace/v0"
    var fixtureId: String
    var sourceHash: String
    var platform: TPlatform
    var steps: [TStep]
    var observations: [TObservation]
    var declaredOrder: [TEdge]
    var conditions: [String: String]?   // run conditions (reduceMotion.*), compared exactly and never adaptable; nil = none recorded
}

func encodePretty<T: Encodable>(_ v: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try e.encode(v)
}
