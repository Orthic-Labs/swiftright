import AppKit
import SwiftUI

func arg(_ k: String) -> String? { guard let i = CommandLine.arguments.firstIndex(of: k), i+1 < CommandLine.arguments.count else { return nil }; return CommandLine.arguments[i+1] }
let scale: CGFloat = CGFloat(Double(arg("--scale") ?? "2.5")!)
let mode = arg("--mode") ?? "renderer"
let path = arg("--path") ?? "hstack"
let vert = CommandLine.arguments.contains("--vert")
let W: CGFloat = CGFloat(Double(arg("--w") ?? "320")!)

struct Row { let a: Double; let w: Double; var k: Int = 0 }
nonisolated(unsafe) var geo: [Int: (Double, Double)] = [:]
struct Probe: View { let k: Int; var body: some View { GeometryReader { g in let f = g.frame(in: .global); let _ = { geo[k] = (Double(f.minX), Double(f.maxX)) }(); Color.clear } } }

@ViewBuilder func rowView(_ r: Row) -> some View {
    switch path {
    case "hstack": HStack(spacing: 0) { Color.clear.frame(width: r.a, height: 4); Color.red.frame(width: r.w, height: 4); Spacer(minLength: 0) }
    case "hgeo": HStack(spacing: 0) { Color.clear.frame(width: r.a, height: 4); Color.red.frame(width: r.w, height: 4).overlay(Probe(k: r.k)); Spacer(minLength: 0) }
    case "padding": HStack(spacing: 0) { Color.red.frame(width: r.w, height: 4).padding(.leading, r.a); Spacer(minLength: 0) }
    case "offset": HStack(spacing: 0) { Color.red.frame(width: r.w, height: 4).offset(x: r.a); Spacer(minLength: 0) }
    case "spacing": HStack(spacing: r.a) { Color.clear.frame(width: 0, height: 4); Color.red.frame(width: r.w, height: 4); Spacer(minLength: 0) }
    case "center": Color.red.frame(width: r.w, height: 4).frame(width: 2*r.a + r.w, height: 4).frame(width: W, alignment: .leading)
    case "nested": HStack(spacing: 0) { Color.clear.frame(width: r.a/2, height: 4); Color.clear.frame(width: r.a/2, height: 4); Color.red.frame(width: r.w, height: 4); Spacer(minLength: 0) }
    case "overlay": Color.clear.frame(width: W, height: 4).overlay(alignment: .leading) { Color.red.frame(width: r.w, height: 4).padding(.leading, r.a) }
    case "bg": Color.clear.frame(width: r.a + r.w, height: 4).background(alignment: .trailing) { Color.red.frame(width: r.w, height: 4) }.frame(width: W, alignment: .leading)
    case "shape": HStack(spacing: 0) { Color.clear.frame(width: r.a, height: 4); Rectangle().fill(Color.red).frame(width: r.w, height: 4); Spacer(minLength: 0) }
    case "split": // a = a1 + a2 where a1 = floor(a/3 * 10)/10 style: split a into a1 = a*0.37 (dyadic-rounded) and a2 = a - a1
        let a1 = (r.a * 0.375), a2 = r.a - a1
        HStack(spacing: 0) { Color.clear.frame(width: a1, height: 4); HStack(spacing: 0) { Color.clear.frame(width: a2, height: 4); Color.red.frame(width: r.w, height: 4) } ; Spacer(minLength: 0) }
    case "split2": let a1 = (r.a * 0.375), a2 = r.a - a1
        HStack(spacing: 0) { Color.clear.frame(width: a1, height: 4); Color.red.frame(width: r.w, height: 4).padding(.leading, a2); Spacer(minLength: 0) }
    case "container": // child positioned inside a container that is itself at a1
        let a1 = r.a * 0.375, a2 = r.a - a1
        HStack(spacing: 0) { ZStack(alignment: .leading) { Color.clear; Color.red.frame(width: r.w, height: 4).offset(x: a2) }.frame(width: a1 + a2 + r.w, height: 4).offset(x: a1); Spacer(minLength: 0) }
    default: EmptyView()
    }
}

func content(_ rows: [Row]) -> some View {
    if vert { return AnyView(HStack(alignment: .top, spacing: 0) { ForEach(0..<rows.count, id: \.self) { i in VStack(spacing: 0) { Color.clear.frame(width: 4, height: rows[i].a); Color.red.frame(width: 4, height: rows[i].w); Spacer(minLength: 0) } } }.frame(height: W, alignment: .top).background(Color.white).environment(\.colorScheme, .light)) }
    return AnyView(VStack(spacing: 0) { ForEach(0..<rows.count, id: \.self) { rowView(rows[$0]) } }
        .frame(width: W, alignment: .leading).background(Color.white).environment(\.colorScheme, .light))
}

final class Win: NSWindow { override var backingScaleFactor: CGFloat { scale } }

@MainActor func render(_ rows: [Row]) -> (Int, Int, [UInt8])? {
    let CW: CGFloat = vert ? CGFloat(rows.count * 4) : W
    let H = vert ? W : CGFloat(rows.count * 4)
    let view = content(rows)
    let pw = Int(CW * scale), ph = Int(H * scale)
    if mode == "cg" || mode == "cgflip" {
        var buf = [UInt8](repeating: 255, count: pw*ph*4)
        let ctx = CGContext(data: &buf, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(false)
        if mode == "cgflip" { ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: scale, y: -scale) } else { ctx.scaleBy(x: scale, y: scale) }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        for (k, r) in rows.enumerated() { ctx.fill(CGRect(x: r.a, y: Double(k)*4, width: r.w, height: 4)) }
        return (pw, ph, buf)
    }
    if mode == "renderer" {
        let r = ImageRenderer(content: view); r.scale = scale
        guard let img = r.cgImage else { return nil }
        var buf = [UInt8](repeating: 0, count: img.width*img.height*4)
        let ctx = CGContext(data: &buf, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return (img.width, img.height, buf)
    } else {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: CW, height: H)
        let win = Win(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = host.bounds.size
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        host.displayIgnoringOpacity(host.bounds, in: ctx)
        var buf = [UInt8](repeating: 0, count: pw*ph*4)
        for y in 0..<ph { for x in 0..<pw { var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: x, y: y); for c in 0..<4 { buf[(y*pw+x)*4+c] = UInt8(p[c]) } } }
        return (pw, ph, buf)
    }
}

var rows: [Row] = []
while let line = readLine() { let p = line.split(separator: " ").compactMap { Double($0) }; if p.count == 2 { rows.append(Row(a: p[0], w: p[1], k: rows.count)) } }
let batch = 400
@MainActor func run() {
    var i = 0
    while i < rows.count {
        let chunk = Array(rows[i..<min(i+batch, rows.count)])
        guard let (pw, ph, buf) = render(chunk) else { print("render failed"); return }
        for (k, r) in chunk.enumerated() {
            let y = Int((Double(k)*4+2)*Double(scale))
            var total = 0.0, first = -1, last = -1
            for x in 0..<(vert ? ph : pw) {
                let o = vert ? (x*pw + y)*4 : (y*pw+x)*4; let g = Double(buf[o+1]); let cov = (255 - g)/255
                if cov > 0.01 { if first < 0 { first = x }; last = x }
                total += cov
            }
            let g = geo[r.k] ?? (-1,-1)
            print(String(format: "%g %g L=%d R=%d cov=%.3f expL=%.4f expR=%.4f", r.a, r.w, first, last+1, total, r.a*Double(scale), (r.a+r.w)*Double(scale)) + " GL=\(g.0) GR=\(g.1)")
        }
        i += batch
    }
}
MainActor.assumeIsolated { _ = NSApplication.shared; run() }
