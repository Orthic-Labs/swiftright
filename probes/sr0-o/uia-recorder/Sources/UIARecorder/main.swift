import Foundation
import UIAKit

// UIARecorder record --pid N --steps steps.json --out trace.json [--sidecar extra.json] [--toolchain "Swift 6.4.0"]
// UIARecorder tree   --pid N [--out tree.json]
// Exit: 0 ok, 1 one or more ops failed (trace still written), 2 usage/attach error.

func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func arg(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func write(_ data: Data, to path: String) throws {
    try data.write(to: URL(fileURLWithPath: path))
}

#if os(Windows)
func run(_ args: [String]) throws -> Int32 {
    guard let cmd = args.first, let pidS = arg("--pid", args), let pid = Int(pidS) else {
        err("usage: UIARecorder record --pid N --steps steps.json --out trace.json [--sidecar f] | tree --pid N [--out f]")
        return 2
    }
    let toolchain = arg("--toolchain", args) ?? "Swift 6.4.0 (swift-6.4-RELEASE)"
    switch cmd {
    case "tree":
        let empty = FixtureSteps(fixtureId: "tree", sourceHash: "")
        let rec = try Recorder(RecorderOptions(pid: pid, steps: empty, toolchain: toolchain))
        let tree = rec.snapshotTree()
        let data = try encodeJSON(tree)
        let norm = WinNormalizer.normalize(tree)
        print(String(decoding: data, as: UTF8.self))
        print("--- canonical ---")
        print(String(decoding: try encodeJSON(norm.nodes), as: UTF8.self))
        if let out = arg("--out", args) { try write(data, to: out) }
        return 0
    case "record":
        guard let stepsPath = arg("--steps", args), let out = arg("--out", args) else { err("record needs --steps and --out"); return 2 }
        let steps = try JSONDecoder().decode(FixtureSteps.self, from: Data(contentsOf: URL(fileURLWithPath: stepsPath)))
        let rec = try Recorder(RecorderOptions(pid: pid, steps: steps, toolchain: toolchain))
        let (trace, side, ok) = rec.run()
        try write(try encodeJSON(trace), to: out)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let sp = arg("--sidecar", args) { try write(try enc.encode(side), to: sp) }
        print("wrote \(out) steps=\(trace.steps.count) ok=\(ok)")
        return ok ? 0 : 1
    default:
        err("unknown command \(cmd)")
        return 2
    }
}
do { exit(try run(Array(CommandLine.arguments.dropFirst()))) } catch { err("UIARecorder: \(error)"); exit(2) }
#else
err("UIARecorder is Windows-only (UI Automation). Use UIACompare on this platform.")
exit(2)
#endif
