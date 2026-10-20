import SwiftUI
import CoreGraphics

// This file imports SwiftUI only: SwiftRightRuntime declares its own Path, Circle, Color, StrokeStyle and so on, so the two worlds
// live in separate files (RuntimeRender.swift mirrors every case below, point for point).

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)          // 51, 153, 255
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)        // 255, 102, 51

@MainActor
private func referenceView(_ name: String) -> AnyView? {
    switch name {
    case "ring-trim-round":
        return AnyView(Circle().inset(by: 3).trim(from: 0, to: 0.62)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60))
    case "ring-trim-dashed-butt":
        return AnyView(Circle().inset(by: 3).trim(from: 0, to: 0.62)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [4, 2])).rotationEffect(.degrees(-90)).frame(width: 60, height: 60))
    case "ring-track-dashed":
        return AnyView(Circle().inset(by: 3)
            .stroke(blue.opacity(0.7), style: StrokeStyle(lineWidth: 6, dash: [4, 2])).rotationEffect(.degrees(-90)).frame(width: 60, height: 60))
    case "ring-trim-tiny":
        return AnyView(Circle().inset(by: 3).trim(from: 0, to: 0.02)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60))
    case "ring-trim-zero":
        return AnyView(Circle().inset(by: 3).trim(from: 0, to: 0)
            .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60))
    case "path-fill-nonzero":
        return AnyView(pentagram().fill(orange).frame(width: 60, height: 60))
    case "path-fill-evenodd":
        return AnyView(pentagram().fill(orange, style: FillStyle(eoFill: true)).frame(width: 60, height: 60))
    case "path-joins":
        // miter (ratio 2.85), miter past the limit (ratio 10.6 > 10, falls back to a bevel), round, bevel
        return AnyView(ZStack {
            zigzag(x0: 5, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10))
            zigzag(x0: 45, dx: 4).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10))
            zigzag(x0: 85, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            zigzag(x0: 125, dx: 15).stroke(blue, style: StrokeStyle(lineWidth: 6, lineJoin: .bevel))
        }.frame(width: 160, height: 60))
    case "path-curves":
        return AnyView(curves().stroke(blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).frame(width: 100, height: 100))
    case "stroke-hairline":
        return AnyView(ZStack {
            hline(y: 6).stroke(blue, lineWidth: 0.4)
            hline(y: 15).stroke(blue, lineWidth: 0.5)
            hline(y: 24).stroke(blue, lineWidth: 1)
        }.frame(width: 60, height: 30))
    case "dash-phase":
        return AnyView(Path { p in p.move(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 55, y: 10)) }
            .stroke(blue, style: StrokeStyle(lineWidth: 4, dash: [6, 3], dashPhase: 2)).frame(width: 60, height: 20))
    default:
        return nil
    }
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

/// The SwiftUI reference bitmap of one case: ImageRenderer at `spikeScale`, redrawn into sRGB premultiplied RGBA.
@MainActor
func renderReference(_ info: CaseInfo) -> Bitmap? {
    guard let view = referenceView(info.name) else { return nil }
    let renderer = ImageRenderer(content: view)
    renderer.scale = CGFloat(spikeScale)
    guard let image = renderer.cgImage else { return nil }
    return Bitmap(cgImage: image)
}
