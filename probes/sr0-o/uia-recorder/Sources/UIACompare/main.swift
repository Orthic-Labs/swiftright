import Foundation
import TraceKit

// UIACompare <accepted.json> <candidate.json> [--adapt adaptations.json] [--json]
// accepted = Mac oracle (or hand-written expected) trace, candidate = Windows trace.
// Exit: 0 pass, 1 diffs, 2 usage/load error. Timestamps and platform tuple are never compared (TraceKit rule).

func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    err("usage: UIACompare <accepted.json> <candidate.json> [--adapt adaptations.json] [--json]")
    exit(2)
}

do {
    func load(_ p: String) throws -> Trace { try TraceCodec.decode(Data(contentsOf: URL(fileURLWithPath: p))) }
    var adaptations: [Adaptation] = []
    if let i = args.firstIndex(of: "--adapt"), i + 1 < args.count {
        adaptations = try JSONDecoder().decode([Adaptation].self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
    }
    let accepted = try load(args[0]), candidate = try load(args[1])
    let report = TraceComparator.compare(accepted: accepted, candidate: candidate, adaptations: adaptations)
    if args.contains("--json") {
        print(String(decoding: try TraceCodec.json(report), as: UTF8.self))
    } else {
        print("fixture \(report.fixture): accepted=\(accepted.platform.os) candidate=\(candidate.platform.os)")
        for n in report.notes { print("note: \(n)") }
        if report.diffs.isEmpty {
            print("PASS: 0 diffs")
        } else {
            print("FAIL: \(report.diffs.count) diff(s)")
            for d in report.diffs {
                print("  step=\(d.step)  path=\(d.path)\n    expected: \(d.expected)\n    actual:   \(d.actual)")
            }
        }
    }
    exit(report.passed ? 0 : 1)
} catch {
    err("UIACompare: \(error)")
    exit(2)
}
