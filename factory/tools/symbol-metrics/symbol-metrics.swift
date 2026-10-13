// Derives per-symbol LAYOUT metrics (never outlines) from this Mac, offscreen (no window):
//  * NSImage(systemSymbolName:) imageSize / alignmentRect / ink box at a reference point size (reference data);
//  * the SwiftUI resizable+scaledToFit layout box aspect and ink box placement inside it, measured from
//    ImageRenderer output (this is what the Windows provider must reproduce);
//  * the SwiftUI intrinsic size of Image(systemName:) at the default font;
//  * a verification pass: predicted vs measured ink bbox at other frame shapes.
// Build+run from the internal disk via symbol-metrics.sh.   usage: symbol-metrics.sh [--point-size N] [--config scale:WxH]... name...  -> JSON on stdout.
import AppKit
import SwiftUI

var pointSize: CGFloat = 13
var names: [String] = []
var configs: [(scale: Double, w: Int, h: Int)] = []   // --config 2.5:32x32  (screen scale : frame in points)
var it = Array(CommandLine.arguments.dropFirst()).makeIterator()
while let a = it.next() {
    if a == "--point-size", let v = it.next(), let d = Double(v) { pointSize = CGFloat(d) }
    else if a == "--config", let v = it.next() {
        let p = v.split(separator: ":"), wh = p.count == 2 ? p[1].split(separator: "x") : []
        guard wh.count == 2, let sc = Double(p[0]), let w = Int(wh[0]), let h = Int(wh[1]) else { fatalError("--config scale:WxH") }
        configs.append((sc, w, h))
    } else { names.append(a) }
}

struct Ink { var x0: Double, y0: Double, x1: Double, y1: Double
    var w: Double { x1 - x0 }; var h: Double { y1 - y0 } }

func alphaInk(_ cg: CGImage) -> Ink? {
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))   // memory row 0 == top row
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 < 0 ? nil : Ink(x0: Double(x0), y0: Double(y0), x1: Double(x1 + 1), y1: Double(y1 + 1))
}

func nsImageInk(_ image: NSImage) -> Ink? {
    let o: CGFloat = 32
    let w = Int((image.size.width * o).rounded(.up)), h = Int((image.size.height * o).rounded(.up))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.black.set()
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage, var ink = alphaInk(cg) else { return nil }
    let sx = Double(image.size.width) / Double(w), sy = Double(image.size.height) / Double(h)
    ink.x0 *= sx; ink.x1 *= sx; ink.y0 *= sy; ink.y1 *= sy
    return ink
}

struct ViewFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
nonisolated(unsafe) var capturedViewFrame: CGRect = .zero

/// Renders resizable+scaledToFit in a w x h pt container at a screen scale; returns the alpha>=128 ink box (px, in the
/// container) and SwiftUI's own Image view frame (pt, in the container, captured with GeometryReader, never assumed).
@MainActor func render(_ name: String, scale: Double, w: Int, h: Int) -> (ink: Ink, view: CGRect)? {
    capturedViewFrame = .zero
    let view = Image(systemName: name).resizable().scaledToFit()
        .background(GeometryReader { g in Color.clear.preference(key: ViewFrameKey.self, value: g.frame(in: .named("c"))) })
        .frame(width: CGFloat(w), height: CGFloat(h))
        .coordinateSpace(name: "c")
        .foregroundStyle(Color.black)
        .onPreferenceChange(ViewFrameKey.self) { capturedViewFrame = $0 }
    let r = ImageRenderer(content: view); r.scale = CGFloat(scale)
    guard let cg = r.cgImage, cg.width == Int((Double(w) * scale).rounded()), let k = alphaInk(cg),
          capturedViewFrame.width > 0 else { return nil }
    return (k, capturedViewFrame)
}

/// One device configuration: ink box in whole pixels relative to the pixel-snapped view origin (edges rounded half up, as
/// the Windows runtime snaps frames); it may extend past the view.
@MainActor func deviceInk(_ name: String, scale: Double, w: Int, h: Int) -> [String: Any]? {
    guard let (k, f) = render(name, scale: scale, w: w, h: h) else { return nil }
    func snap(_ v: CGFloat) -> Int { Int((Double(v) * scale + 0.5).rounded(.down)) }
    let l = snap(f.minX), t = snap(f.minY), rr = snap(f.maxX), bb = snap(f.maxY)
    return ["scale": scale, "containerPt": [w, h],
            "viewFramePt": [Double(f.minX), Double(f.minY), Double(f.width), Double(f.height)],
            "viewFramePx": [l, t, rr - l, bb - t],
            "fitIntrinsicSize": rationalSize(Double(f.width / f.height)),   // what SwiftUI fitted at this device config
            "inkBoxPx": [Int(k.x0) - l, Int(k.y0) - t, Int(k.x1) - l, Int(k.y1) - t],
            "inkBoxInContainerPx": [Int(k.x0), Int(k.y0), Int(k.x1), Int(k.y1)]]
}

@MainActor func naturalSize(_ name: String) -> [Double] {
    let s = NSHostingView(rootView: Image(systemName: name)).fittingSize
    return [Double(s.width), Double(s.height)]
}

/// Small integer w x h whose ratio equals the measured scaledToFit aspect (the size SwiftUI fits resizable symbols by).
func rationalSize(_ aspect: Double) -> [Double] {
    for h in 1...256 { let w = (aspect * Double(h)).rounded()
        if abs(w / Double(h) - aspect) < 1e-6 * aspect { return [w, Double(h)] } }
    return [aspect * 100, 100]
}

@MainActor func measure(_ name: String) -> [String: Any] {
    let S = 2048
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let image = base.withSymbolConfiguration(cfg), let nsInk = nsImageInk(image),
          let (ink, view) = render(name, scale: 1, w: S, h: S) else { return ["error": "symbol unavailable"] }
    // Linear model: SwiftUI's Image view frame (aspect-fit of the scaledToFit intrinsic aspect) and the ink as fractions of it.
    let aspect = Double(view.width / view.height)
    let fr = [(ink.x0 - Double(view.minX)) / Double(view.width), (ink.y0 - Double(view.minY)) / Double(view.height),
              (ink.x1 - Double(view.minX)) / Double(view.width), (ink.y1 - Double(view.minY)) / Double(view.height)]
    var worst = 0.0
    var checks: [[String: Any]] = []
    for (fw, fh) in [(1536, 1024), (1024, 1536), (1000, 1000), (2560, 640), (640, 2560), (800, 200)] {
        guard let (m, v) = render(name, scale: 1, w: fw, h: fh) else { continue }
        let p = [Double(v.minX) + fr[0] * Double(v.width), Double(v.minY) + fr[1] * Double(v.height),
                 Double(v.minX) + fr[2] * Double(v.width), Double(v.minY) + fr[3] * Double(v.height)]
        let err = max(abs(p[0] - m.x0), abs(p[1] - m.y0), abs(p[2] - m.x1), abs(p[3] - m.y1))
        worst = max(worst, err)
        checks.append(["container": [fw, fh], "measured": [m.x0, m.y0, m.x1, m.y1], "predicted": p, "maxErrorPx": err])
    }
    let al = image.alignmentRect
    return [
        "aspect": aspect,                                   // Image view frame width / height under scaledToFit
        "inkRect": fr,                                      // ink as fractions of that view frame, top-down [x0,y0,x1,y1]
        "intrinsicSize": naturalSize(name),                 // natural size of Image(systemName:) (fixed, non-resizable use)
        "fitIntrinsicSize": rationalSize(aspect),           // size SwiftUI scales for resizable().scaledToFit()
        "nsImage": ["imageSize": [Double(image.size.width), Double(image.size.height)],
                    "alignmentRect": [Double(al.minX), Double(image.size.height - al.maxY), Double(al.maxX), Double(image.size.height - al.minY)],
                    "inkBox": [nsInk.x0, nsInk.y0, nsInk.x1, nsInk.y1]],
        "deviceInk": configs.compactMap { deviceInk(name, scale: $0.scale, w: $0.w, h: $0.h) },
        "verification": ["worstErrorPxAtLargeFrames": worst, "frames": checks],
    ]
}

let out: [String: Any] = MainActor.assumeIsolated {
    var syms: [String: Any] = [:]
    for n in names { syms[n] = measure(n) }
    return ["referencePointSize": Double(pointSize), "weight": "regular", "scale": "medium",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "method": "SwiftUI ImageRenderer offscreen, resizable+scaledToFit, alpha>=128 ink; view frame from GeometryReader", "symbols": syms]
}
let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
