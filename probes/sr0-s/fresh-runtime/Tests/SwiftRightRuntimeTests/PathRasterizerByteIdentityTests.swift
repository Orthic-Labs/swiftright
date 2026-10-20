import Foundation
@testable import SwiftRightRuntime
import XCTest

/// The optimised stroke coverage and stroke-only compositing in `PathRasterizer.rasterize` must produce the same RGBA bytes
/// as the straightforward evaluation kept as `PathRasterizer.rasterizeReference` (the pre-optimisation algorithm, verbatim).
/// Inputs: the F-path parity cases (probes/sr0-s/fresh-runtime/Tools/PathParitySpike RuntimeRender.swift) and seeded random paths.
final class PathRasterizerByteIdentityTests: XCTestCase {
    private let blue: UInt32 = 0x3399ffff
    private let blueSeventy: UInt32 = 0x3399ffb3
    private let orange: UInt32 = 0xff6633ff

    private func assertIdentical(_ path: Path, transform: CGAffineTransform = .identity, scale: CGFloat,
                                 fill: UInt32? = nil, fillStyle: FillStyle = FillStyle(),
                                 stroke: UInt32? = nil, style: StrokeStyle = StrokeStyle(),
                                 _ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fast = try PathRasterizer.rasterize(path: path, transform: transform, scale: scale, fillRGBA: fill, fillStyle: fillStyle,
                                                strokeRGBA: stroke, strokeStyle: style)
        let reference = try PathRasterizer.rasterizeReference(path: path, transform: transform, scale: scale, fillRGBA: fill, fillStyle: fillStyle,
                                                              strokeRGBA: stroke, strokeStyle: style)
        XCTAssertEqual(fast == nil, reference == nil, "\(label): nil mismatch", file: file, line: line)
        guard let fast, let reference else { return }
        XCTAssertEqual(fast.originX, reference.originX, "\(label): originX", file: file, line: line)
        XCTAssertEqual(fast.originY, reference.originY, "\(label): originY", file: file, line: line)
        XCTAssertEqual(fast.image.width, reference.image.width, "\(label): width", file: file, line: line)
        XCTAssertEqual(fast.image.height, reference.image.height, "\(label): height", file: file, line: line)
        if fast.image.rgba != reference.image.rgba {
            var differing = 0, first = -1
            for i in 0..<min(fast.image.rgba.count, reference.image.rgba.count) where fast.image.rgba[i] != reference.image.rgba[i] {
                differing += 1; if first < 0 { first = i }
            }
            XCTFail("\(label): RGBA differs in \(differing) bytes (first at byte \(first))", file: file, line: line)
        }
    }

    private func rotation(_ degrees: Double, about cx: CGFloat, _ cy: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: cx, y: cy).rotated(by: CGFloat(degrees * Double.pi / 180)).translatedBy(x: -cx, y: -cy)
    }

    private func ringPath(trimTo: CGFloat, trimmed: Bool = true) -> Path {
        var p = Path(); p.addEllipse(in: CGRect(x: 3, y: 3, width: 54, height: 54))
        return (trimmed ? p.trimmedPath(from: 0, to: trimTo) : p).applying(rotation(-90, about: 30, 30))
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

    /// The 11 F-path cases (the joins and hairline cases are several layers each, one comparison per layer), at each scale.
    func testFPathCasesAreByteIdentical() throws {
        for scale: CGFloat in [1, 2, 2.5] {
            try assertIdentical(ringPath(trimTo: 0.62), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineCap: .round), "ring-trim-round @\(scale)")
            try assertIdentical(ringPath(trimTo: 0.62), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [4, 2]), "ring-trim-dashed-butt @\(scale)")
            try assertIdentical(ringPath(trimTo: 1, trimmed: false), scale: scale, stroke: blueSeventy, style: StrokeStyle(lineWidth: 6, dash: [4, 2]), "ring-track-dashed @\(scale)")
            try assertIdentical(ringPath(trimTo: 0.02), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineCap: .round), "ring-trim-tiny @\(scale)")
            try assertIdentical(ringPath(trimTo: 0), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineCap: .round), "ring-trim-zero @\(scale)")
            try assertIdentical(pentagram(), scale: scale, fill: orange, "path-fill-nonzero @\(scale)")
            try assertIdentical(pentagram(), scale: scale, fill: orange, fillStyle: FillStyle(eoFill: true), "path-fill-evenodd @\(scale)")
            try assertIdentical(zigzag(x0: 5, dx: 15), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10), "joins miter @\(scale)")
            try assertIdentical(zigzag(x0: 45, dx: 4), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 10), "joins miter-limit @\(scale)")
            try assertIdentical(zigzag(x0: 85, dx: 15), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .round), "joins round @\(scale)")
            try assertIdentical(zigzag(x0: 125, dx: 15), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 6, lineJoin: .bevel), "joins bevel @\(scale)")
            try assertIdentical(curves(), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), "path-curves @\(scale)")
            try assertIdentical(hline(y: 6), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 0.4), "hairline 0.4 @\(scale)")
            try assertIdentical(hline(y: 15), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 0.5), "hairline 0.5 @\(scale)")
            try assertIdentical(hline(y: 24), scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 1), "hairline 1 @\(scale)")
            var dashed = Path(); dashed.move(to: CGPoint(x: 5, y: 10)); dashed.addLine(to: CGPoint(x: 55, y: 10))
            try assertIdentical(dashed, scale: scale, stroke: blue, style: StrokeStyle(lineWidth: 4, dash: [6, 3], dashPhase: 2), "dash-phase @\(scale)")
        }
    }

    /// The notch ring benchmark input (rotated, scale 2.5), over a spin of angles, and with a fill beneath the stroke.
    func testRingSpinIsByteIdentical() throws {
        var p = Path(); p.addEllipse(in: CGRect(x: 3, y: 3, width: 54, height: 54))
        let trimmed = p.trimmedPath(from: 0, to: 0.62)
        let rot = CGAffineTransform(translationX: 75, y: 75).rotated(by: -.pi / 2).translatedBy(x: -75, y: -75)
        let style = StrokeStyle(lineWidth: 6, lineCap: .round)
        for i in 0..<12 {
            let spin = CGAffineTransform(translationX: 75, y: 75).rotated(by: Double(i) * 0.37).translatedBy(x: -75, y: -75)
            try assertIdentical(trimmed, transform: rot.concatenating(spin), scale: 2.5, stroke: 0x3399ffff, style: style, "ring spin \(i)")
        }
        try assertIdentical(trimmed, transform: rot, scale: 2.5, fill: 0xff6633ff, stroke: 0x3399ffb3, style: style, "ring fill+stroke")
    }

    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
        mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
    }

    func testRandomPathsAreByteIdentical() throws {
        var rng = Rng(state: 0x5EED_0F_5701_E5)
        let caps: [LineCap] = [.butt, .round, .square]
        let joins: [LineJoin] = [.miter, .round, .bevel]
        for caseIndex in 0..<60 {
            func pt() -> CGPoint { CGPoint(x: rng.range(2, 70), y: rng.range(2, 70)) }
            var path = Path()
            for _ in 0..<Int(rng.range(1, 3.99)) {
                path.move(to: pt())
                for _ in 0..<Int(rng.range(1, 6.99)) {
                    switch Int(rng.range(0, 3)) {
                    case 0: path.addLine(to: pt())
                    case 1: path.addQuadCurve(to: pt(), control: pt())
                    default: path.addCurve(to: pt(), control1: pt(), control2: pt())
                    }
                }
                if rng.unit() < 0.4 { path.closeSubpath() }
                if rng.unit() < 0.15 { path.addEllipse(in: CGRect(x: rng.range(0, 40), y: rng.range(0, 40), width: rng.range(4, 30), height: rng.range(4, 30))) }
            }
            let scale = rng.pick([CGFloat(1), 2, 2.5])
            let angle = rng.range(-Double.pi, Double.pi)
            let transform = CGAffineTransform(translationX: CGFloat(rng.range(-5, 20)), y: CGFloat(rng.range(-5, 20)))
                .rotated(by: CGFloat(angle)).translatedBy(x: -20, y: -20)
            var style = StrokeStyle(lineWidth: CGFloat(rng.range(0.3, 9)), lineCap: rng.pick(caps), lineJoin: rng.pick(joins),
                                    miterLimit: CGFloat(rng.range(1, 12)))
            if rng.unit() < 0.35 {
                style.dash = [CGFloat(rng.range(0.5, 8)), CGFloat(rng.range(0.5, 6))]
                style.dashPhase = CGFloat(rng.range(0, 10))
            }
            let wantFill = rng.unit() < 0.4
            let wantStroke = !wantFill || rng.unit() < 0.7
            try assertIdentical(path, transform: transform, scale: scale,
                                fill: wantFill ? 0xff6633ff : nil, fillStyle: FillStyle(eoFill: rng.unit() < 0.5),
                                stroke: wantStroke ? 0x3399ffb3 : nil, style: style, "random #\(caseIndex)")
        }
    }

    /// Regression: an open curve whose end tangents differ strongly cuts a segment's quad square to those tangents, which can make it a
    /// non-convex (bow-tie) polygon. The reference drops such a piece at pixels whose centre is outside it and 0.7072+ from its boundary,
    /// even where its half-planes still contain samples; the optimised path must replay that filter.
    func testNonConvexEndTangentQuadsAreByteIdentical() throws {
        var rng = Rng(state: 0xB0B7_1E)
        for index in 0..<120 {
            var p = Path()
            let a = CGPoint(x: rng.range(10, 30), y: rng.range(10, 30)), b = CGPoint(x: rng.range(10, 30), y: rng.range(10, 30))
            p.move(to: a)
            p.addCurve(to: b, control1: CGPoint(x: rng.range(-30, 80), y: rng.range(-30, 80)), control2: CGPoint(x: rng.range(-30, 80), y: rng.range(-30, 80)))
            let style = StrokeStyle(lineWidth: CGFloat(rng.range(3, 14)), lineCap: .butt, lineJoin: .miter)
            try assertIdentical(p, scale: rng.pick([CGFloat(1), 2, 2.5]), stroke: 0x3399ffb3, style: style, "bow-tie sweep #\(index)")
        }
    }
}
