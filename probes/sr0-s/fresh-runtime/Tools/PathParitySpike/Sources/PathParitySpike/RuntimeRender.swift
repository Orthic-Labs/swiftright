import Foundation
import CoreGraphics
import SwiftRightRuntime

// This file imports SwiftRightRuntime only (SwiftUIReference.swift imports SwiftUI; the two declare clashing names).
// Every case mirrors SwiftUIReference.swift point for point, built through the runtime's SwiftUI-shaped API.

private let blue: UInt32 = 0x3399ffff            // 51, 153, 255
private let blueSeventy: UInt32 = 0x3399ffb3     // opacity 0.7 -> alpha 179
private let orange: UInt32 = 0xff6633ff          // 255, 102, 51

private struct Layer {
    var path: Path
    var fill: UInt32?
    var fillStyle = FillStyle()
    var stroke: UInt32?
    var style = StrokeStyle()
}

/// Rotation by `degrees` (clockwise on screen) about (cx, cy), in points.
private func rotation(_ degrees: Double, about cx: CGFloat, _ cy: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: cx, y: cy).rotated(by: CGFloat(degrees * Double.pi / 180)).translatedBy(x: -cx, y: -cy)
}

private func ring(trimTo: CGFloat, style: StrokeStyle, color: UInt32, trimmed: Bool = true) -> [Layer] {
    let frame = CGRect(x: 0, y: 0, width: 60, height: 60)
    let geometry = trimmed ? Circle().inset(by: 3).trim(from: 0, to: trimTo).shapeGeometry : Circle().inset(by: 3).shapeGeometry
    return [Layer(path: geometry.makePath(in: frame).applying(rotation(-90, about: 30, 30)), stroke: color, style: style)]
}

private func pentagram() -> Path {
    Path { p in
        func vertex(_ k: Int) -> CGPoint {
            let a = -Double.pi / 2 + Double(k) * 2 * Double.pi / 5
            return CGPoint(x: 30 + 26 * cos(a), y: 30 + 26 * sin(a))
        }
        p.move(to: vertex(0)); p.addLine(to: vertex(2)); p.addLine(to: vertex(4)); p.addLine(to: vertex(1)); p.addLine(to: vertex(3))
        p.closeSubpath()
    }
}

private func zigzag(x0: CGFloat, dx: CGFloat) -> Path {
    Path { p in
        p.move(to: CGPoint(x: x0, y: 52)); p.addLine(to: CGPoint(x: x0 + dx, y: 8)); p.addLine(to: CGPoint(x: x0 + 2 * dx, y: 52))
    }
}

private func hline(y: CGFloat) -> Path {
    Path { p in p.move(to: CGPoint(x: 5, y: y)); p.addLine(to: CGPoint(x: 55, y: y)) }
}

private func curves() -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 10, y: 60))
    p.addQuadCurve(to: CGPoint(x: 40, y: 60), control: CGPoint(x: 25, y: 20))
    p.addCurve(to: CGPoint(x: 70, y: 60), control1: CGPoint(x: 50, y: 95), control2: CGPoint(x: 60, y: 95))
    p.addArc(center: CGPoint(x: 80, y: 30), radius: 12, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
    p.addEllipse(in: CGRect(x: 10, y: 10, width: 30, height: 18))
    p.addPath(Path(ellipseIn: CGRect(x: 0, y: 0, width: 16, height: 10)).applying(CGAffineTransform(scaleX: 1.5, y: 1.5)).offsetBy(dx: 55, dy: 70))
    return p
}

private func layers(_ name: String) -> [Layer]? {
    switch name {
    case "ring-trim-round": return ring(trimTo: 0.62, style: StrokeStyle(lineWidth: 6, lineCap: .round), color: blue)
    case "ring-trim-dashed-butt": return ring(trimTo: 0.62, style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [4, 2]), color: blue)
    case "ring-track-dashed": return ring(trimTo: 1, style: StrokeStyle(lineWidth: 6, dash: [4, 2]), color: blueSeventy, trimmed: false)
    case "ring-trim-tiny": return ring(trimTo: 0.02, style: StrokeStyle(lineWidth: 6, lineCap: .round), color: blue)
    case "ring-trim-zero": return ring(trimTo: 0, style: StrokeStyle(lineWidth: 6, lineCap: .round), color: blue)
    case "path-fill-nonzero": return [Layer(path: pentagram(), fill: orange)]
    case "path-fill-evenodd": return [Layer(path: pentagram(), fill: orange, fillStyle: FillStyle(eoFill: true))]
    case "path-joins":
        return [Layer(path: zigzag(x0: 5, dx: 15), stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10)),
                Layer(path: zigzag(x0: 45, dx: 4), stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10)),
                Layer(path: zigzag(x0: 85, dx: 15), stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .round)),
                Layer(path: zigzag(x0: 125, dx: 15), stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .bevel))]
    case "path-curves": return [Layer(path: curves(), stroke: blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))]
    case "stroke-hairline":
        return [Layer(path: hline(y: 6), stroke: blue, style: StrokeStyle(lineWidth: 0.4)),
                Layer(path: hline(y: 15), stroke: blue, style: StrokeStyle(lineWidth: 0.5)),
                Layer(path: hline(y: 24), stroke: blue, style: StrokeStyle(lineWidth: 1))]
    case "dash-phase":
        var p = Path(); p.move(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 55, y: 10))
        return [Layer(path: p, stroke: blue, style: StrokeStyle(lineWidth: 4, dash: [6, 3], dashPhase: 2))]
    default: return nil
    }
}

/// The PathRasterizer bitmap of one case on the same canvas as the reference (premultiplied, for comparison).
func renderRuntime(_ info: CaseInfo) throws -> Bitmap? {
    guard let layers = layers(info.name) else { return nil }
    var canvas = Bitmap(width: Int((Double(info.widthPt) * spikeScale).rounded()), height: Int((Double(info.heightPt) * spikeScale).rounded()))
    for layer in layers {
        guard let r = try PathRasterizer.rasterize(path: layer.path, transform: .identity, scale: CGFloat(spikeScale),
                                                   fillRGBA: layer.fill, fillStyle: layer.fillStyle,
                                                   strokeRGBA: layer.stroke, strokeStyle: layer.style) else { continue }
        canvas.composite(straight: r.image.rgba, width: r.image.width, height: r.image.height, atX: r.originX, y: r.originY)
    }
    return canvas
}
