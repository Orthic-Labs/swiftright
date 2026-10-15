import Foundation
import SwiftRightRuntime
import SwiftRightHost

// I1 decode dump: decodes every corpus case through SwiftRightImageIO (WIC on Windows, ImageIO on the Mac) and writes
//   OUT/results.json   per case: result (ok | threw), error text, width, height, offset and length in run.bin, FNV contentID, CGImage surface facts
//   OUT/run.bin        the decoded RGBA8 buffers, concatenated
// and, with --old, the same for the pure-Swift block 35 decoder (ImageDecoder.Backend.swift) into OUT/old-results.json and OUT/old-run.bin.
// usage: ImageDump CORPUS_DIR OUT_DIR [--old]

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: ImageDump CORPUS_DIR OUT_DIR [--old]"); exit(2) }
let corpus = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: corpus.appendingPathComponent("manifest.json"))) as! [String: Any]
let cases = manifest["cases"] as! [[String: Any]]

func run(_ label: String, _ decode: (Data, Int) throws -> (RGBAImage, [String: Any])) throws {
    var bin = Data(); var rows: [[String: Any]] = []
    for c in cases {
        let id = c["id"] as! String, file = c["file"] as! String, mp = c["maxPixel"] as? Int ?? 0
        var row: [String: Any] = ["id": id, "kind": c["kind"] as! String, "maxPixel": mp]
        let started = Date()
        do {
            let data = try Data(contentsOf: corpus.appendingPathComponent(file))
            if (c["kind"] as? String) == "negative", label.isEmpty { row["codecOnly"] = SwiftRightImageIO.codecOnlyProbe(data: data) }
            let (image, facts) = try decode(data, mp)
            row["result"] = "ok"; row["w"] = image.width; row["h"] = image.height; row["offset"] = bin.count; row["length"] = image.rgba.count
            row["contentID"] = String(image.contentID, radix: 16)
            for (k, v) in facts { row[k] = v }
            bin.append(contentsOf: image.rgba)
        } catch {
            row["result"] = "threw"; row["error"] = "\(error)"
        }
        row["ms"] = Int(Date().timeIntervalSince(started) * 1000)
        rows.append(row)
    }
    let prefix = label.isEmpty ? "" : label + "-"
    try bin.write(to: out.appendingPathComponent("\(prefix)run.bin"))
    let meta: [String: Any] = ["decoder": label.isEmpty ? "SwiftRightImageIO" : label, "cases": rows]
    try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("\(prefix)results.json"))
}

try run("") { data, mp in
    let image = try SwiftRightImageIO.makeImage(data: data, maxPixel: mp)
    #if os(Windows)
    return (image.pixels, ["cgWidth": image.width, "cgHeight": image.height, "cgBitsPerComponent": image.bitsPerComponent, "cgAlphaInfo": Int(image.alphaInfo.rawValue), "cgColorSpace": image.colorSpaceName])
    #else
    return (try SwiftRightImageIO.decodePixels(data: data, maxPixel: mp), ["cgWidth": image.width, "cgHeight": image.height, "cgBitsPerComponent": image.bitsPerComponent, "cgAlphaInfo": Int(image.alphaInfo.rawValue)])
    #endif
}
if args.contains("--old") {
    try run("old") { data, mp in
        ImageDecoder.backend = .swift
        return (try ImageDecoder.decode(data, maxPixel: mp), [:])
    }
}
print("ImageDump: \(cases.count) cases -> \(out.path)")
