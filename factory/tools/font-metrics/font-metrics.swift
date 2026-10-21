// font-metrics: the Mac font metric table for SwiftRight (docs/foundations-images-fonts.md block F1).
// Measures SwiftUI (one-line Text frame height, first and last baseline, width) in an NSHostingView inside an offscreen window that never reaches a screen
// and whose backing scale is pinned (decision C12; scales 1, 1.25, 1.5 and 2.5; 1.25 and 1.5 added for #70), and CoreText (ascent, descent, leading, capHeight, xHeight) for the same fonts.
// Output: one JSON document on stdout, deterministic (no clock, no paths, sorted keys, doubles rounded to 1e-4). usage: font-metrics --fonts <dir> --variants <dir> [--quick]
// <dir> of --fonts holds Tinos-Regular.ttf (factory/resources/fonts); --variants is the scratch dir written by make-variants.py.
import AppKit
import SwiftUI
import CoreText

let toolVersion = "font-metrics-1"
func arg(_ k: String) -> String? { let a = CommandLine.arguments; guard let i = a.firstIndex(of: k), i + 1 < a.count else { return nil }; return a[i + 1] }
let quick = CommandLine.arguments.contains("--quick")
guard let fontsDir = arg("--fonts"), let variantsDir = arg("--variants") else { FileHandle.standardError.write(Data("usage: font-metrics --fonts <dir> --variants <dir> [--quick]\n".utf8)); exit(64) }

func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
func num(_ v: Double) -> String { String(format: "%g", v) }

// ---- pinned offscreen host ----
final class PinnedWindow: NSWindow { nonisolated(unsafe) static var pinned: CGFloat = 2.5; override var backingScaleFactor: CGFloat { Self.pinned } }
struct Seen { nonisolated(unsafe) static var scale: Double = -1; nonisolated(unsafe) static var h = 0.0, w = 0.0, fb = 0.0, lb = 0.0, called = 0 }
struct Probe: View {
    @Environment(\.displayScale) private var displayScale
    var body: some View { Seen.scale = Double(displayScale); return Color.clear.frame(width: 1, height: 1) }
}
nonisolated(unsafe) var windows: [Double: PinnedWindow] = [:]
@MainActor func window(_ scale: Double) -> PinnedWindow {
    if let w = windows[scale] { return w }
    PinnedWindow.pinned = CGFloat(scale)
    let w = PinnedWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .aqua)
    windows[scale] = w
    return w
}

/// [height, firstBaseline, lastBaseline, width] of the view's own size and text guides, in points, at the pinned scale.
@MainActor func measure<V: View>(_ v: V, scale: Double) -> [Double] {
    PinnedWindow.pinned = CGFloat(scale)
    Seen.scale = -1; Seen.called = 0
    let root = v.fixedSize()
        .alignmentGuide(.leading) { d in Seen.h = Double(d.height); Seen.w = Double(d.width); Seen.fb = Double(d[.firstTextBaseline]); Seen.lb = Double(d[.lastTextBaseline]); Seen.called += 1; return 0 }
        .background(Probe())
        .frame(width: 900, height: 300, alignment: .topLeading)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 300)
    let win = window(scale)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    if Seen.called == 0 || Seen.scale < 0 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)); host.layoutSubtreeIfNeeded() }
    if Seen.called == 0 || abs(Seen.scale - scale) > 1e-9 {
        FileHandle.standardError.write(Data("scale guard failed: called=\(Seen.called) displayScale=\(Seen.scale) wanted=\(scale)\n".utf8)); exit(2)
    }
    return [r4(Seen.h), r4(Seen.fb), r4(Seen.lb), r4(Seen.w)]
}

struct Ink { var coverage = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0, slantMilli = 0, digest = "", bgRed = 0 }
/// Draws the text black at the pinned scale into a bitmap (the capture-host path; coverage = 255 - red over the white the view paints) and reads its ink.
@MainActor func renderInk<V: View>(_ v: V, scale: Double) -> Ink {
    PinnedWindow.pinned = CGFloat(scale)
    let W = 520, H = 70
    let root = v.fixedSize().foregroundStyle(Color.black).frame(width: CGFloat(W), height: CGFloat(H), alignment: .topLeading).background(Color.white).environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: W, height: H)
    let win = window(scale); win.contentView = host
    for _ in 0..<3 { host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)) }
    let pw = Int((Double(W) * scale).rounded()), ph = Int((Double(H) * scale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return Ink() }
    rep.size = host.bounds.size   // before the context exists: the context takes its scale from it
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return Ink() }
    host.displayIgnoringOpacity(host.bounds, in: ctx)
    guard let cg = rep.cgImage else { return Ink() }
    var px = [UInt8](repeating: 0, count: pw * ph * 4)
    guard let c2 = CGContext(data: &px, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Ink() }
    c2.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
    var ink = Ink(); ink.x0 = pw; ink.y0 = ph; ink.x1 = -1; ink.y1 = -1
    var rowSum = [Double](repeating: 0, count: ph), rowX = [Double](repeating: 0, count: ph)
    var h: UInt64 = 0xcbf29ce484222325
    ink.bgRed = Int(px[0])
    for y in 0..<ph { for x in 0..<pw {
        let c = 255 - Int(px[(y * pw + x) * 4])   // black text on the white background the view paints
        h = (h ^ UInt64(c)) &* 0x100000001b3
        if c > 0 { ink.coverage += c; rowSum[y] += Double(c); rowX[y] += Double(c * x); ink.x0 = min(ink.x0, x); ink.x1 = max(ink.x1, x + 1); ink.y0 = min(ink.y0, y); ink.y1 = max(ink.y1, y + 1) }
    } }
    ink.digest = String(h, radix: 16)
    if ink.y1 > ink.y0 {
        let mid = (ink.y0 + ink.y1) / 2
        func centroid(_ a: Int, _ b: Int) -> Double { var s = 0.0, t = 0.0; for y in a..<b { s += rowSum[y]; t += rowX[y] }; return s > 0 ? t / s : 0 }
        ink.slantMilli = Int(((centroid(ink.y0, mid) - centroid(mid, ink.y1)) * 1000).rounded())   // positive: the top leans right of the bottom
    }
    return ink
}

// ---- tables ----
let weightNames = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
let swiftWeights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
let nsWeights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
let designNames = ["default", "monospaced", "serif", "rounded"]
let swiftDesigns: [Font.Design] = [.default, .monospaced, .serif, .rounded]
let nsDesigns: [NSFontDescriptor.SystemDesign?] = [nil, .monospaced, .serif, .rounded]
let styleNames = ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2"]
let swiftStyles: [Font] = [.largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .footnote, .caption, .caption2]
let nsStyles: [NSFont.TextStyle] = [.largeTitle, .title1, .title2, .title3, .headline, .subheadline, .body, .callout, .footnote, .caption1, .caption2]
let scales: [Double] = [1, 1.25, 1.5, 2.5]
let sample = "Hamburgefonstiv"
nonisolated(unsafe) var faceNames: [String] = []
func faceIndex(_ n: String) -> Int { if let i = faceNames.firstIndex(of: n) { return i }; faceNames.append(n); return faceNames.count - 1 }

func ctRow(_ f: NSFont) -> [Any] {
    let c = f as CTFont
    return [r4(Double(CTFontGetAscent(c))), r4(Double(CTFontGetDescent(c))), r4(Double(CTFontGetLeading(c))), r4(Double(CTFontGetCapHeight(c))), r4(Double(CTFontGetXHeight(c))), r4(Double(CTFontGetUnitsPerEm(c))), faceIndex(CTFontCopyPostScriptName(c) as String)]
}
func nsSystem(_ size: Double, _ w: NSFont.Weight, _ d: NSFontDescriptor.SystemDesign?) -> NSFont {
    let base = NSFont.systemFont(ofSize: CGFloat(size), weight: w)
    guard let d else { return base }
    guard let desc = base.fontDescriptor.withDesign(d), let f = NSFont(descriptor: desc, size: CGFloat(size)) else { return base }
    return f
}
func styleFont(_ i: Int, weight: NSFont.Weight?) -> NSFont {
    let f = NSFont.preferredFont(forTextStyle: nsStyles[i])
    guard let weight else { return f }
    let d = f.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
    return NSFont(descriptor: d, size: f.pointSize) ?? f
}

// ---- main ----
let out: [String: Any] = MainActor.assumeIsolated {
    var result: [String: Any] = [:]
    let os = ProcessInfo.processInfo
    result["tool"] = toolVersion
    result["macOS"] = os.operatingSystemVersionString
    var sizeBuf = 0; sysctlbyname("kern.osversion", nil, &sizeBuf, nil, 0)
    var buf = [CChar](repeating: 0, count: max(sizeBuf, 1)); sysctlbyname("kern.osversion", &buf, &sizeBuf, nil, 0)
    result["macOSBuild"] = String(cString: buf)
    result["scales"] = scales
    result["sample"] = sample
    result["columns"] = ["swiftUI": ["height", "firstBaseline", "lastBaseline", "width"], "coreText": ["ascent", "descent", "leading", "capHeight", "xHeight", "unitsPerEm", "faceIndex"]]

    // A. Font.system(size:weight:design:) at 9...40 step 0.5, nine weights, four designs
    var swiftSys: [String: Any] = [:], ctSys: [String: Any] = [:]
    var sizes: [Double] = []; var s = 9.0; while s <= 40 { sizes.append(s); s += 0.5 }
    if quick { sizes = [9, 13, 13.5, 40] }
    for (di, dn) in designNames.enumerated() {
        for (wi, wn) in weightNames.enumerated() {
            for sz in sizes {
                let key = "\(dn)|\(wn)|\(num(sz))"
                ctSys[key] = ctRow(nsSystem(sz, nsWeights[wi], nsDesigns[di]))
                for sc in scales { swiftSys["\(key)|\(num(sc))"] = measure(Text(sample).font(.system(size: CGFloat(sz), weight: swiftWeights[wi], design: swiftDesigns[di])), scale: sc) }
            }
        }
    }
    result["swiftUISystem"] = swiftSys; result["coreTextSystem"] = ctSys

    // B. text styles: as is, with each weight, bold(), italic(), and the four designs
    var swiftStyle: [String: Any] = [:], ctStyle: [String: Any] = [:], ctStyleInfo: [String: Any] = [:]
    for (i, st) in styleNames.enumerated() {
        let base = styleFont(i, weight: nil)
        let traits = (base.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]) ?? [:]
        ctStyleInfo[st] = ["pointSize": r4(Double(base.pointSize)), "weightTrait": r4(((traits[.weight] as? NSNumber)?.doubleValue ?? 0)), "postScript": base.fontName]
        ctStyle["\(st)|default"] = ctRow(base)
        for (wi, wn) in weightNames.enumerated() { ctStyle["\(st)|\(wn)"] = ctRow(styleFont(i, weight: nsWeights[wi])) }
        for sc in scales {
            let k = num(sc)
            swiftStyle["\(st)|default|\(k)"] = measure(Text(sample).font(swiftStyles[i]), scale: sc)
            for (wi, wn) in weightNames.enumerated() { swiftStyle["\(st)|\(wn)|\(k)"] = measure(Text(sample).font(swiftStyles[i].weight(swiftWeights[wi])), scale: sc) }
            swiftStyle["\(st)|bold()|\(k)"] = measure(Text(sample).font(swiftStyles[i].bold()), scale: sc)
            swiftStyle["\(st)|italic()|\(k)"] = measure(Text(sample).font(swiftStyles[i].italic()), scale: sc)
        }
    }
    // styled system fonts with a design (Font.system(style, design:)) and the NSFont equivalent
    for (i, st) in styleNames.enumerated() {
        let textStyles: [Font.TextStyle] = [.largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .footnote, .caption, .caption2]
        for sc in scales { for (di, dn) in designNames.enumerated() { swiftStyle["\(st)|design-\(dn)|\(num(sc))"] = measure(Text(sample).font(Font.system(textStyles[i], design: swiftDesigns[di])), scale: sc) } }
        for (di, dn) in designNames.enumerated() {
            let base = styleFont(i, weight: nil)
            if let d = nsDesigns[di], let desc = base.fontDescriptor.withDesign(d), let f = NSFont(descriptor: desc, size: base.pointSize) { ctStyle["\(st)|design-\(dn)"] = ctRow(f) } else { ctStyle["\(st)|design-\(dn)"] = ctRow(base) }
        }
    }
    result["swiftUIStyles"] = swiftStyle; result["coreTextStyles"] = ctStyle; result["coreTextStyleInfo"] = ctStyleInfo

    // C. synthesis: bold and italic on a single-face bundled family (Tinos Regular) against a family that has real faces (Helvetica)
    let tinosURL = URL(fileURLWithPath: fontsDir).appendingPathComponent("Tinos-Regular.ttf") as CFURL
    var preRegistered = false
    if NSFont(name: "Tinos-Regular", size: 20) != nil { preRegistered = true }
    var cfErr: Unmanaged<CFError>?
    let registered = CTFontManagerRegisterFontsForURL(tinosURL, .process, &cfErr)
    var syn: [String: Any] = ["tinosInstalledBeforeRegistration": preRegistered, "tinosRegistered": registered]
    func variantsOf(_ name: String, _ size: Double) -> [(String, Font)] {
        let f = Font.custom(name, size: CGFloat(size))
        return [("regular", f), ("bold()", f.bold()), ("weight(bold)", f.weight(.bold)), ("weight(black)", f.weight(.black)), ("italic()", f.italic()), ("bold().italic()", f.bold().italic())]
    }
    let synScales: [Double] = [2.5]
    for family in ["Tinos", "Helvetica"] {
        for (label, f) in variantsOf(family, 24) {
            let m = measure(Text(sample).font(f), scale: 1)
            let ink = renderInk(Text(sample + " HIL").font(f), scale: 2.5)
            syn["swiftUI|\(family)|\(label)"] = ["width": m[3], "height": m[0], "firstBaseline": m[1], "coverage": ink.coverage, "inkBox": [ink.x0, ink.y0, ink.x1, ink.y1], "slantMilliPx": ink.slantMilli, "digest": ink.digest, "background": ink.bgRed]
        }
        let tv = Text(sample + " HIL").font(.custom(family, size: 24))
        let inkT = renderInk(tv.bold(), scale: 2.5), inkF = renderInk(tv.fontWeight(.bold), scale: 2.5), inkI = renderInk(tv.italic(), scale: 2.5), inkP = renderInk(tv, scale: 2.5)
        syn["swiftUI|\(family)|Text.bold()"] = ["coverage": inkT.coverage, "digest": inkT.digest]
        syn["swiftUI|\(family)|fontWeight(bold)"] = ["coverage": inkF.coverage, "digest": inkF.digest]
        syn["swiftUI|\(family)|Text.italic()"] = ["coverage": inkI.coverage, "slantMilliPx": inkI.slantMilli, "digest": inkI.digest]
        syn["swiftUI|\(family)|plainAgain"] = ["coverage": inkP.coverage, "digest": inkP.digest]
        // CoreText and AppKit: which face does a bold or italic request pick, and with what advance
        guard let plain = NSFont(name: family == "Tinos" ? "Tinos-Regular" : "Helvetica", size: 24) else { syn["coreText|\(family)"] = "font not found"; continue }
        var ct: [String: Any] = ["plainFace": plain.fontName]
        func line(_ f: NSFont) -> Double { let l = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: f])); return r4(CTLineGetTypographicBounds(l, nil, nil, nil)) }
        ct["plainWidth"] = line(plain)
        for (label, trait) in [("bold", CTFontSymbolicTraits.traitBold), ("italic", .traitItalic), ("bold+italic", [.traitBold, .traitItalic])] {
            if let c = CTFontCreateCopyWithSymbolicTraits(plain as CTFont, 24, nil, trait, trait) { ct["CTCopyWithSymbolicTraits|\(label)"] = ["face": CTFontCopyPostScriptName(c) as String, "width": line(c as NSFont)] } else { ct["CTCopyWithSymbolicTraits|\(label)"] = "nil (no such face)" }
            let desc = plain.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: trait.rawValue))
            if let f = NSFont(descriptor: desc, size: 24) { ct["NSFontDescriptor|\(label)"] = ["face": f.fontName, "width": line(f)] }
        }
        let fm = NSFontManager.shared
        let b = fm.convert(plain, toHaveTrait: .boldFontMask), it = fm.convert(plain, toHaveTrait: .italicFontMask)
        ct["NSFontManager|bold"] = ["face": b.fontName, "width": line(b)]; ct["NSFontManager|italic"] = ["face": it.fontName, "width": line(it)]
        let wdesc = plain.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.bold.rawValue]])
        if let f = NSFont(descriptor: wdesc, size: 24) { ct["NSFontDescriptor|weightTrait bold"] = ["face": f.fontName, "width": line(f)] }
        syn["coreText|\(family)"] = ct
        _ = synScales
    }
    result["synthesis"] = syn

    // D. Font.custom name resolution, singles and collisions, on throwaway variants of Tinos (distinct ascent per file) and on Tinos itself
    var lookup: [String: Any] = [:]
    let vurl = URL(fileURLWithPath: variantsDir)
    let meta = (try? JSONSerialization.jsonObject(with: Data(contentsOf: vurl.appendingPathComponent("variants.json")))) as? [String: [String: Any]] ?? [:]
    var heightOf: [String: Double] = [:], labelByPS: [String: String] = [:]
    for (label, m) in meta.sorted(by: { $0.key < $1.key }) {
        let u = vurl.appendingPathComponent("\(label).ttf") as CFURL
        var e: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(u, .process, &e) { lookup["registerFailed|\(label)"] = true }
        let ps = m["postScript"] as! String; labelByPS[ps] = label
        if let f = NSFont(name: ps, size: 20) { heightOf[label] = Double(CTFontGetAscent(f as CTFont).rounded() + CTFontGetDescent(f as CTFont).rounded()) }
    }
    let sysH = measure(Text(sample).font(.system(size: 20)), scale: 1)[0]
    func identify(_ h: Double) -> String {
        for (label, vh) in heightOf.sorted(by: { $0.key < $1.key }) where abs(vh - h) < 0.75 { return label }
        if abs(h - sysH) < 0.75 { return "unresolved (system font)" }
        return "unknown height \(h)"
    }
    var tinosH = 0.0; if let f = NSFont(name: "Tinos-Regular", size: 20) { tinosH = Double(CTFontGetAscent(f as CTFont).rounded() + CTFontGetDescent(f as CTFont).rounded()) }
    let queries = ["ZqSingleFam", "ZqSinglePS", "Zq Single Full", "ZqCollide1", "ZqCollide2", "ZqCollide3", "ZqCollide4",
                   "Tinos", "Tinos Regular", "Tinos-Regular", "tinos", "TINOS-REGULAR", "tinos regular", "Tinos Bold", "Tinos-Bold", "ZqCollide1 ", "zqcollide1", "ZQSINGLEFAM"]
    for q in queries {
        var row: [String: Any] = [:]
        for sc in scales {
            let h = measure(Text(sample).font(.custom(q, size: 20)), scale: sc)
            let who = abs(h[0] - tinosH) < 0.75 && h[0] != sysH ? "Tinos" : identify(h[0])
            row["swiftUI@\(num(sc))"] = ["height": h[0], "firstBaseline": h[1], "resolved": who]
        }
        if let f = NSFont(name: q, size: 20) { row["NSFont(name:)"] = f.fontName } else { row["NSFont(name:)"] = "nil" }
        let c = CTFontCreateWithName(q as CFString, 20, nil); row["CTFontCreateWithName"] = CTFontCopyPostScriptName(c) as String
        lookup[q] = row
    }
    var variantInfo: [String: Any] = [:]
    for (label, m) in meta.sorted(by: { $0.key < $1.key }) { variantInfo[label] = ["id": m["id"] ?? 0, "family": m["family"] ?? "", "postScript": m["postScript"] ?? "", "fullName": m["fullName"] ?? "", "lineHeightAt20": heightOf[label] ?? -1] }
    lookup["_variants"] = variantInfo
    lookup["_systemHeightAt20"] = sysH; lookup["_tinosHeightAt20"] = tinosH
    result["lookup"] = lookup

    // E. mixed-script lines
    var mixed: [String: Any] = [:]
    let lines: [(String, String)] = [
        ("latin", "Hello World"), ("japanese", "こんにちは世界"), ("chinese", "你好世界"), ("korean", "안녕하세요"), ("emoji", "😀🎉"),
        ("latin+ja", "Hello こんにちは"), ("latin+zh", "Hello 你好"), ("latin+ko", "Hello 안녕하세요"), ("latin+emoji", "Hello 😀"),
        ("all", "Hello こんにちは 你好 안녕 😀"), ("han", "直骨"), ("arabic", "مرحبا"), ("hindi", "नमस्ते"), ("thai", "สวัสดี"),
    ]
    let fontsForMixed: [(String, Font, NSFont)] = [("system13", .system(size: 13), NSFont.systemFont(ofSize: 13)), ("system17", .system(size: 17), NSFont.systemFont(ofSize: 17)), ("body", .body, styleFont(6, weight: nil)),
                                                    ("system40", .system(size: 40), NSFont.systemFont(ofSize: 40)), ("tinos20", .custom("Tinos", size: 20), NSFont(name: "Tinos-Regular", size: 20)!)]
    for (fname, sf, nf) in fontsForMixed {
        for (lname, text) in lines {
            var row: [String: Any] = [:]
            for sc in scales { row["swiftUI@\(num(sc))"] = measure(Text(text).font(sf), scale: sc) }
            let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: nf]))
            var a: CGFloat = 0, d: CGFloat = 0, g: CGFloat = 0
            let w = CTLineGetTypographicBounds(l, &a, &d, &g)
            var runFonts: [String] = []
            for run in (CTLineGetGlyphRuns(l) as! [CTRun]) {
                let at = CTRunGetAttributes(run) as NSDictionary
                let f = at[kCTFontAttributeName as String] as! CTFont
                let n = CTFontCopyPostScriptName(f) as String
                if runFonts.last != n { runFonts.append(n) }
            }
            row["coreTextLine"] = ["ascent": r4(Double(a)), "descent": r4(Double(d)), "leading": r4(Double(g)), "width": r4(w)]
            row["runFaces"] = runFonts
            mixed["\(fname)|\(lname)"] = row
        }
    }
    for loc in ["ja", "zh-Hans", "zh-Hant", "ko", "en"] {
        for sc in scales { mixed["system13|han|locale-\(loc)|\(num(sc))"] = measure(Text("直骨").font(.system(size: 13)).environment(\.locale, Locale(identifier: loc)), scale: sc) }
    }
    result["mixedScripts"] = mixed
    result["faceNames"] = faceNames
    return result
}
let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
