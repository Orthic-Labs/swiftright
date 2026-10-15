// Non-resizable (font-sized) SF Symbol layout measurements from this Mac, offscreen (ImageRenderer; no window).
// For each symbol x point size x screen scale: SwiftUI's own Image view frame (pt, GeometryReader, never assumed), the
// NSHostingView fitting size, and the alpha>=128 ink box in device pixels relative to the pixel-snapped view frame.
// usage: symbol-sizes [--sizes 10,13,...] [--scales 1,2.5] [--weight regular] [--style body] name...  -> JSON on stdout.
import AppKit
import SwiftUI

var sizes: [String] = ["10", "11", "12", "13", "14", "15", "17", "20", "22", "28"]   // a number = Font.system(size:); or default, largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
var scales: [Double] = [1, 2.5]
var names: [String] = []
var weightName = "regular"
var it = Array(CommandLine.arguments.dropFirst()).makeIterator()
while let a = it.next() {
    if a == "--sizes", let v = it.next() { sizes = v.split(separator: ",").map(String.init) }
    else if a == "--scales", let v = it.next() { scales = v.split(separator: ",").compactMap { Double($0) } }
    else if a == "--weight", let v = it.next() { weightName = v }
    else if a == "--capture-path" { }
    else { names.append(a) }
}

func weight(_ n: String) -> Font.Weight {
    switch n { case "ultraLight": return .ultraLight; case "thin": return .thin; case "light": return .light; case "medium": return .medium
    case "semibold": return .semibold; case "bold": return .bold; case "heavy": return .heavy; case "black": return .black; default: return .regular }
}

struct ViewFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
nonisolated(unsafe) var captured: CGRect = .zero

func alphaInk(_ cg: CGImage) -> [Int]? {
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 < 0 ? nil : [x0, y0, x1 + 1, y1 + 1]
}

func styleFont(_ s: String) -> Font? {
    switch s { case "largeTitle": return .largeTitle; case "title": return .title; case "title2": return .title2; case "title3": return .title3
    case "headline": return .headline; case "subheadline": return .subheadline; case "body": return .body; case "callout": return .callout
    case "footnote": return .footnote; case "caption": return .caption; case "caption2": return .caption2; default: return nil }
}

@MainActor func measure(_ name: String, size: String, scale: Double) -> [String: Any] {
    captured = .zero
    let pad: CGFloat = 8
    let font: Font? = Double(size).map { Font.system(size: CGFloat($0), weight: weight(weightName)) } ?? styleFont(size)
    let view = Image(systemName: name).font(font).foregroundStyle(Color.black)
        .background(GeometryReader { g in Color.clear.preference(key: ViewFrameKey.self, value: g.frame(in: .named("c"))) })
        .frame(width: 120, height: 120, alignment: .topLeading)
        .coordinateSpace(name: "c")
        .onPreferenceChange(ViewFrameKey.self) { captured = $0 }
    let r = ImageRenderer(content: view); r.scale = CGFloat(scale)
    guard let cg = r.cgImage, let ink = alphaInk(cg), captured.width > 0 else { return ["error": "render failed"] }
    let f = captured
    func snap(_ v: CGFloat) -> Int { Int((Double(v) * scale + 0.5).rounded(.down)) }
    let l = snap(f.minX), t = snap(f.minY), rr = snap(f.maxX), bb = snap(f.maxY)
    let fit = NSHostingView(rootView: Image(systemName: name).font(font)).fittingSize
    _ = pad
    return ["viewFramePt": [Double(f.minX), Double(f.minY), Double(f.width), Double(f.height)],
            "fittingSizePt": [Double(fit.width), Double(fit.height)],
            "viewFramePx": [l, t, rr - l, bb - t],
            "inkBoxPx": [ink[0] - l, ink[1] - t, ink[2] - l, ink[3] - t]]
}

// Capture-path measurement: the witness hosted in an NSHostingView inside an offscreen borderless window that never reaches a screen, drawn at the
// capture scale into a bitmap exactly as the Mac capture host of the paired cases does (factory/pipeline/blocks-26-34/shared-mac-host). A font-sized symbol is
// drawn by the text pipeline there, which differs from ImageRenderer by up to 2 px at a sharp tip; this is the path the cases are compared against.
final class PinnedWindow: NSWindow { nonisolated(unsafe) static var pinned: CGFloat = 2.5; override var backingScaleFactor: CGFloat { Self.pinned } }

@MainActor func measureCapture(_ name: String, size: String, scale: Double) -> [String: Any] {
    captured = .zero
    PinnedWindow.pinned = CGFloat(scale)
    let font: Font? = Double(size).map { Font.system(size: CGFloat($0), weight: weight(weightName)) } ?? styleFont(size)
    let view = Image(systemName: name).font(font).foregroundStyle(Color.black)
        .background(GeometryReader { g in Color.clear.preference(key: ViewFrameKey.self, value: g.frame(in: .named("c"))) })
        .frame(width: 120, height: 120, alignment: .topLeading)
        .coordinateSpace(name: "c")
        .onPreferenceChange(ViewFrameKey.self) { captured = $0 }
        .background(Color.white)
    let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .light)))
    host.frame = NSRect(x: 0, y: 0, width: 120, height: 120)
    let window = PinnedWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    for _ in 0..<3 { host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)) }
    let pw = Int((120 * scale).rounded())
    guard captured.width > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: pw, bitsPerSample: 8, samplesPerPixel: 4,
                                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return ["error": "capture failed"] }
    rep.size = host.bounds.size
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return ["error": "context failed"] }
    host.displayIgnoringOpacity(host.bounds, in: ctx)
    guard let cg = rep.cgImage else { return ["error": "no image"] }
    var px = [UInt8](repeating: 0, count: pw * pw * 4)
    guard let c2 = CGContext(data: &px, width: pw, height: pw, bitsPerComponent: 8, bytesPerRow: pw * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return ["error": "ctx2"] }
    c2.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: pw))
    var x0 = pw, y0 = pw, x1 = -1, y1 = -1
    for y in 0..<pw { for x in 0..<pw where px[(y * pw + x) * 4] <= 127 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }   // black over white: half coverage
    guard x1 >= 0 else { return ["error": "no ink"] }
    let f = captured
    func snap(_ v: CGFloat) -> Int { Int((Double(v) * scale + 0.5).rounded(.down)) }
    let l = snap(f.minX), t = snap(f.minY), rr = snap(f.maxX), bb = snap(f.maxY)
    return ["viewFramePt": [Double(f.minX), Double(f.minY), Double(f.width), Double(f.height)], "viewFramePx": [l, t, rr - l, bb - t],
            "inkBoxPx": [x0 - l, y0 - t, x1 + 1 - l, y1 + 1 - t]]
}

let useCapture = CommandLine.arguments.contains("--capture-path")
let out: [String: Any] = MainActor.assumeIsolated {
    var syms: [String: Any] = [:]
    for n in names {
        var per: [String: Any] = [:]
        for s in sizes { for sc in scales { per["\(s)@\(sc)"] = useCapture ? measureCapture(n, size: s, scale: sc) : measure(n, size: s, scale: sc) } }
        syms[n] = per
    }
    return ["weight": weightName, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "method": (CommandLine.arguments.contains("--capture-path") ? "NSHostingView in an offscreen pinned-scale window drawn into a bitmap (the capture host path)," : "SwiftUI ImageRenderer offscreen,") + " non-resizable Image(systemName:).font(.system(size:)); view frame from GeometryReader", "symbols": syms]
}
let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
