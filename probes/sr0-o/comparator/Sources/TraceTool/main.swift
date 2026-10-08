import Foundation
import TraceKit

// sr0o-trace compare <accepted.json> <candidate.json> [--adapt adaptations.json]
// sr0o-trace repeat <run1.json> <run2.json> ...
// Exit codes: 0 pass, 1 fail (diffs or disagreement), 2 usage or load error.

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func loadTrace(_ path: String) throws -> Trace {
    try TraceCodec.decode(Data(contentsOf: URL(fileURLWithPath: path)))
}

func run(_ args: [String]) throws -> Int32 {
    guard let command = args.first else {
        writeStderr("usage: sr0o-trace compare <accepted> <candidate> [--adapt file] | repeat <trace>...")
        return 2
    }
    switch command {
    case "compare":
        guard args.count >= 3 else {
            writeStderr("compare needs <accepted> <candidate>")
            return 2
        }
        var adaptations: [Adaptation] = []
        if let i = args.firstIndex(of: "--adapt"), i + 1 < args.count {
            adaptations = try JSONDecoder().decode([Adaptation].self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
        }
        let report = TraceComparator.compare(accepted: try loadTrace(args[1]), candidate: try loadTrace(args[2]),
                                             adaptations: adaptations)
        print(String(decoding: try TraceCodec.json(report), as: UTF8.self))
        return report.passed ? 0 : 1
    case "repeat":
        let paths = Array(args.dropFirst())
        guard !paths.isEmpty else {
            writeStderr("repeat needs at least one trace")
            return 2
        }
        let report = Repeatability.check(try paths.map(loadTrace))
        print(String(decoding: try TraceCodec.json(report), as: UTF8.self))
        return report.allAgree ? 0 : 1
    default:
        writeStderr("unknown command \(command)")
        return 2
    }
}

do {
    exit(try run(Array(CommandLine.arguments.dropFirst())))
} catch {
    writeStderr("sr0o-trace: \(error)")
    exit(2)
}
