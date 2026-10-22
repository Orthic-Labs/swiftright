import Foundation
import SwiftRightRuntime

/// `.shadow(color:radius:x:y:)` (#82): the shadow of a subtree is its opaque shapes' alpha, blurred with a Gaussian of standard deviation `radius` points, offset by (x, y)
/// points and tinted `color`; it paints beneath the subtree. Fitted to macOS 27 (ImageRenderer, 1x, radius 4 and 8, black on white): the alpha at the shape's edge is 0.48 (a
/// Gaussian step edge gives 0.5 at the edge pixel centre 0.5 px inside) and at distance d it follows 1 - Phi(d / radius), so sigma = radius.
/// Leaves that cast a shadow: shapes (fill or stroke), Color, Gradient and Image (their frame); Text and bitmap alpha are not traced (a Text casts no shadow here, counted).
enum ShadowRaster {
    /// The tinted, blurred, offset bitmap and where it is drawn (window pixels), or nil when the subtree casts nothing.
    static func render(_ root: ResolvedNode, shadow: ResolvedShadow, scale: Float, place: (Rect) -> Rect, rgba: UInt32) throws -> (image: ContinuousRGBAImage, placement: Rect)? {
        var layers: [(alpha: [UInt8], x: Int, y: Int, w: Int, h: Int)] = []
        func leaf(_ n: ResolvedNode) throws {
            guard n.opacity > 0 else { return }
            let p = n.pixelFrame
            let bounds = place(Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height)))
            switch n.kind {
            case "Rectangle", "RoundedRectangle", "Circle", "Capsule", "Path":
                guard let shape = n.shape else { return }
                let paint = shape.paint ?? ShapePaint.implicitFill(foreground: n.style.foreground)
                let stroke = paint.kind == .stroke
                let request = PathShapeRequest(bounds: bounds, scale: scale, geometry: shape.geometry, fillRGBA: stroke ? nil : 0xffffffff, strokeRGBA: stroke ? 0xffffffff : nil,
                                               strokeStyle: paint.strokeStyle ?? StrokeStyle(lineWidth: paint.lineWidth ?? 0), fillStyle: paint.fillStyle ?? FillStyle())
                guard let result = try PathShapeRaster.render(request) else { return }
                let img = result.image
                var a = [UInt8](repeating: 0, count: img.width * img.height)
                for i in 0..<a.count { a[i] = UInt8((Double(img.rgba[i * 4 + 3]) * n.opacity).rounded()) }
                layers.append((a, Int(result.placement.x.rounded()), Int(result.placement.y.rounded()), img.width, img.height))
            case "Color", "Gradient", "Image":
                let x0 = Int(bounds.x.rounded()), y0 = Int(bounds.y.rounded()), w = Int((bounds.x + bounds.w).rounded()) - x0, h = Int((bounds.y + bounds.h).rounded()) - y0
                guard w > 0, h > 0 else { return }
                layers.append(([UInt8](repeating: UInt8((255 * n.opacity).rounded()), count: w * h), x0, y0, w, h))
            default:
                for c in n.children { try leaf(c) }
            }
        }
        for c in root.children { try leaf(c) }
        guard !layers.isEmpty else { return nil }
        let sigma = max(0, shadow.radius) * Double(scale)
        let margin = Int(ceil(3 * sigma))
        let minX = layers.map(\.x).min()! - margin, minY = layers.map(\.y).min()! - margin
        let maxX = layers.map { $0.x + $0.w }.max()! + margin, maxY = layers.map { $0.y + $0.h }.max()! + margin
        let W = maxX - minX, H = maxY - minY
        guard W > 0, H > 0, W <= 8192, H <= 8192 else { return nil }
        var field = [Float](repeating: 0, count: W * H)
        for l in layers {
            for y in 0..<l.h { for x in 0..<l.w {
                let a = Float(l.alpha[y * l.w + x]) / 255
                guard a > 0 else { continue }
                let i = (l.y + y - minY) * W + (l.x + x - minX)
                field[i] = a + field[i] * (1 - a)
            } }
        }
        if sigma > 0.01 {
            var kernel: [Float] = []
            let r = margin
            var sum: Float = 0
            for k in -r...r { let v = Float(exp(-Double(k * k) / (2 * sigma * sigma))); kernel.append(v); sum += v }
            kernel = kernel.map { $0 / sum }
            func blur(_ src: [Float], horizontal: Bool) -> [Float] {
                var out = [Float](repeating: 0, count: W * H)
                for y in 0..<H { for x in 0..<W {
                    var acc: Float = 0
                    for k in -r...r {
                        let xx = horizontal ? x + k : x, yy = horizontal ? y : y + k
                        guard xx >= 0, xx < W, yy >= 0, yy < H else { continue }
                        acc += src[yy * W + xx] * kernel[k + r]
                    }
                    out[y * W + x] = acc
                } }
                return out
            }
            field = blur(blur(field, horizontal: true), horizontal: false)
        }
        let tint = Float(rgba & 255) / 255
        let red = UInt8((rgba >> 24) & 255), green = UInt8((rgba >> 16) & 255), blue = UInt8((rgba >> 8) & 255)
        var out = [UInt8](repeating: 0, count: W * H * 4)
        var any = false
        for i in 0..<(W * H) {
            let a = UInt8(min(255, (field[i] * tint * 255).rounded()))
            guard a > 0 else { continue }
            out[i * 4] = red; out[i * 4 + 1] = green; out[i * 4 + 2] = blue; out[i * 4 + 3] = a
            any = true
        }
        guard any else { return nil }
        let dx = Float((shadow.x * Double(scale)).rounded()), dy = Float((shadow.y * Double(scale)).rounded())
        return (ContinuousRGBAImage(width: W, height: H, rgba: out), Rect(x: Float(minX) + dx, y: Float(minY) + dy, w: Float(W), h: Float(H)))
    }
}
