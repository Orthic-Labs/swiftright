import Foundation

// PathParitySpike: SwiftUI ImageRenderer vs SwiftRightRuntime.PathRasterizer for the 11 F-path cases at scale 2.5.
//   swift run -c release PathParitySpike [--out DIR] [--case NAME]
// Per case: max abs channel error (premultiplied RGBA8) inside the 1 px edge band, and the count of pixels outside the band that differ at all.
// Gate from the plan: 32 levels in the band, exact (0 differing pixels) outside.

var outDirectory: URL?
var only: String?
var arguments = Array(CommandLine.arguments.dropFirst())
while let flag = arguments.first {
    arguments.removeFirst()
    switch flag {
    case "--out": if let v = arguments.first { outDirectory = URL(fileURLWithPath: v); arguments.removeFirst() }
    case "--case": if let v = arguments.first { only = v; arguments.removeFirst() }
    default: FileHandle.standardError.write(Data("unknown argument \(flag)\n".utf8)); exit(2)
    }
}
if let outDirectory { try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true) }

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

MainActor.assumeIsolated {
    print(pad("case", 24) + pad("size", 10) + pad("refAlpha", 10) + pad("mineAlpha", 11) + pad("bandMax", 9) + pad("bandPx", 8) + pad("outDiffPx", 11) + pad("outMax", 8) + "verdict")
    var failures = 0
    for info in spikeCases where only == nil || only == info.name {
        guard let reference = renderReference(info) else { print(pad(info.name, 24) + "NO REFERENCE"); failures += 1; continue }
        let mine: Bitmap?
        do { mine = try renderRuntime(info) } catch { print(pad(info.name, 24) + "RASTER ERROR \(error)"); failures += 1; continue }
        guard let mine else { print(pad(info.name, 24) + "NO RUNTIME CASE"); failures += 1; continue }
        guard reference.width == mine.width, reference.height == mine.height else {
            print(pad(info.name, 24) + "SIZE MISMATCH reference \(reference.width)x\(reference.height) vs runtime \(mine.width)x\(mine.height)"); failures += 1; continue
        }
        let c = compare(reference: reference, mine: mine)
        let pass = c.bandMax <= 32 && c.outsideDiffPixels == 0
        if !pass { failures += 1 }
        print(pad(info.name, 24) + pad("\(reference.width)x\(reference.height)", 10) + pad(String(format: "%.1f", c.refAlphaSum), 10) + pad(String(format: "%.1f", c.mineAlphaSum), 11)
              + pad("\(c.bandMax)", 9) + pad("\(c.bandPixels)", 8) + pad("\(c.outsideDiffPixels)", 11) + pad("\(c.outsideMax)", 8) + (pass ? "PASS" : "FAIL"))
        if let outDirectory {
            reference.writePNG(outDirectory.appendingPathComponent("\(info.name)-swiftui.png"))
            mine.writePNG(outDirectory.appendingPathComponent("\(info.name)-runtime.png"))
            c.diff.writePNG(outDirectory.appendingPathComponent("\(info.name)-diff.png"))
        }
    }
    print(failures == 0 ? "all cases within the gate" : "\(failures) case(s) outside the gate (measurement, not a defect verdict: read the PNGs with --out)")
}
