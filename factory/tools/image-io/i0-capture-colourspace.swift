import AppKit
import CoreGraphics
import ImageIO
import SwiftUI

// I0 (wave 0, block I1): which colour space are the pixels of the factory's Mac capture path in, and what conversion does CoreGraphics apply to a tagged image?
// The capture path is copied from factory/pipeline/blocks-26-34/shared-mac-host/CaptureHost.template.swift: an NSHostingView in a borderless OffscreenWindow that is
// never ordered onto a screen (ScalePin: backing scale 2.5), drawn by displayIgnoringOpacity into an NSBitmapImageRep with colorSpaceName .deviceRGB.
// The same 8-bit pixels are tagged Display P3, sRGB, Adobe RGB and untagged (device RGB), drawn through `Image(decorative:scale:)`, and the captured bytes are
// compared with CGBitmapContext conversions into sRGB (each rendering intent) and into Display P3.
// usage: i0-capture-colourspace OUTDIR  (prints one JSON object; writes captures as PNG into OUTDIR)

final class OffscreenWindow: NSWindow {
    @objc(hasKeyAppearance) func hasKeyAppearanceOverride() -> Bool { true }
    override var backingScaleFactor: CGFloat { 2.5 }
    override var canBecomeKey: Bool { true }
}
func pump(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

let patches: [(UInt8, UInt8, UInt8)] = [
    (0, 0, 0), (255, 255, 255), (128, 128, 128), (64, 64, 64), (192, 192, 192),
    (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255), (255, 0, 255),
    (200, 50, 50), (50, 200, 50), (50, 50, 200), (230, 120, 30), (30, 120, 230),
    (100, 150, 200), (180, 90, 140), (10, 20, 30), (240, 230, 220), (255, 128, 0), (0, 128, 255), (17, 99, 201), (233, 12, 77),
]
let patchPx = 40
let imagePxW = patchPx * patches.count, imagePxH = patchPx

func rgbaBytes() -> [UInt8] {
    var b = [UInt8](repeating: 255, count: imagePxW * imagePxH * 4)
    for y in 0..<imagePxH { for x in 0..<imagePxW {
        let p = patches[x / patchPx]; let o = (y * imagePxW + x) * 4
        b[o] = p.0; b[o + 1] = p.1; b[o + 2] = p.2
    } }
    return b
}

func makeImage(_ space: CGColorSpace?, bytes: [UInt8]) -> CGImage {
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: imagePxW, height: imagePxH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: imagePxW * 4,
                   space: space ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@MainActor
func capture(_ cg: CGImage, to path: String) -> [UInt8] {
    let widthPt = CGFloat(imagePxW) / 2.5, heightPt = CGFloat(imagePxH) / 2.5
    let root = AnyView(ZStack(alignment: .center) { Image(decorative: cg, scale: 2.5) }
        .frame(width: widthPt, height: heightPt, alignment: .center)
        .background(Color.white).environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); pump(0.4); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let pw = Int((host.bounds.width * 2.5).rounded()), ph = Int((host.bounds.height * 2.5).rounded())
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.bounds.size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    host.displayIgnoringOpacity(host.bounds, in: context)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    var out: [UInt8] = []
    let bpr = rep.bytesPerRow, data = rep.bitmapData!
    let y = ph / 2
    let xoff = (pw - imagePxW) / 2
    for i in 0..<patches.count {
        let x = xoff + i * patchPx + patchPx / 2
        let o = y * bpr + x * 4
        out += [data[o], data[o + 1], data[o + 2], data[o + 3]]
    }
    return out
}

/// What CoreGraphics produces drawing `cg` into an 8-bit premultiplied RGBA context of `space` with `intent`; patch centres.
func convert(_ cg: CGImage, to space: CGColorSpace, intent: CGColorRenderingIntent) -> [UInt8] {
    let ctx = CGContext(data: nil, width: imagePxW, height: imagePxH, bitsPerComponent: 8, bytesPerRow: imagePxW * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setRenderingIntent(intent)
    ctx.interpolationQuality = .none
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: imagePxW, height: imagePxH))
    let d = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var out: [UInt8] = []
    for i in 0..<patches.count { let o = (imagePxH / 2 * imagePxW + i * patchPx + patchPx / 2) * 4; out += [d[o], d[o + 1], d[o + 2], d[o + 3]] }
    return out
}

func maxDiff(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? -1 }

@main struct I0 {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let outDir = CommandLine.arguments[1]
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            let bytes = rgbaBytes()
            let spaces: [(String, CGColorSpace?)] = [
                ("p3", CGColorSpace(name: CGColorSpace.displayP3)), ("srgb", CGColorSpace(name: CGColorSpace.sRGB)),
                ("adobeRGB", CGColorSpace(name: CGColorSpace.adobeRGB1998)), ("deviceRGB", nil),
            ]
            let intents: [(String, CGColorRenderingIntent)] = [("default", .defaultIntent), ("absolute", .absoluteColorimetric), ("relative", .relativeColorimetric),
                                                                 ("perceptual", .perceptual), ("saturation", .saturation)]
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!, p3 = CGColorSpace(name: CGColorSpace.displayP3)!
            var report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "patches": patches.count]
            var rows: [[String: Any]] = []
            let identity: [UInt8] = patches.flatMap { [$0.0, $0.1, $0.2, UInt8(255)] }
            for (name, space) in spaces {
                let cg = makeImage(space, bytes: bytes)
                let cap = capture(cg, to: "\(outDir)/capture-\(name).png")
                var row: [String: Any] = ["tag": name, "maxDiffToUnchangedNumbers": maxDiff(cap, identity)]
                for (iname, intent) in intents {
                    row["toSRGB-\(iname)"] = maxDiff(cap, convert(cg, to: srgb, intent: intent))
                    row["toP3-\(iname)"] = maxDiff(cap, convert(cg, to: p3, intent: intent))
                }
                row["toDevice-default"] = maxDiff(cap, convert(cg, to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent))
                row["capturedPatches"] = (0..<patches.count).map { Array(cap[$0 * 4..<$0 * 4 + 3]).map { Int($0) } }
                rows.append(row)
            }
            report["rows"] = rows
            let p3img = makeImage(p3, bytes: bytes)
            var intentRows: [String: Int] = [:]
            let base = convert(p3img, to: srgb, intent: .defaultIntent)
            for (iname, intent) in intents { intentRows[iname] = maxDiff(base, convert(p3img, to: srgb, intent: intent)) }
            report["p3ToSRGB_intentVsDefault_maxDiff"] = intentRows
            report["p3ToSRGB_default"] = (0..<patches.count).map { Array(base[$0 * 4..<$0 * 4 + 3]).map { Int($0) } }
            let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(outDir)/capture-p3.png") as CFURL, nil)!
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
            report["capturePNGColorSpaceName"] = (img.colorSpace?.name as String?) ?? "nil"
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
            report["capturePNGProps"] = props.keys.sorted()
            let json = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8)!)
        }
    }
}
