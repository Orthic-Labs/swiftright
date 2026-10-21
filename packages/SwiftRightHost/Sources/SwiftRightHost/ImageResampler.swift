import Foundation

/// Device-pixel-exact image resampling (wave 1 block I2, docs/foundations-images-fonts.md 1.3 and 1.4; decisions G50 to G58 in docs/sr1-decisions.md).
///
/// The host resamples an image to the node's exact device-pixel size and registers it 1:1, so the GPU sampler never decides a gated pixel. The filter per
/// `Image.Interpolation` level is FITTED to the Mac (ImageRenderer at scale 2.5, macOS 27.0.1 build 26A434) by factory/pipeline/blocks-w1-i2/i2fit.py on the calibration images, and
/// gated on other images. What the fit measured (all on straight-alpha sources resampled premultiplied, gamma-encoded, with the whole source mapped onto the snapped rect):
///   - `.none`: nearest neighbour, source index = floor((t + 0.5) * source / destination) in device pixels.
///   - `.low` and no modifier: bilinear (triangle) sampled at the destination pixel centre, NOT widened on a reduction (it aliases when shrinking).
///   - `.medium`: the same bilinear after 2 x 2 box halvings while the reduction is more than 2:1 (a mip chain).
///   - `.high`: the same mip chain, then a cubic with Mitchell-Netravali parameters `ImageResampler.highCubic`, sampled at the pixel centre, not widened.
///   - an INTERPOLATING source (`RGBAImage.interpolates`, CoreGraphics' shouldInterpolate; every image decoded through ImageIO / `ImageDecoder`) with no `.interpolation` modifier, on an axis that
///     REDUCES: Catmull-Rom (Mitchell B 0, C 0.5) widened by the reduction (support 2 x ratio), sampled at CORNER-ALIGNED centres c(t) = t * (source - 1) / (output - 1) + 0.5 (not the pixel centre), the
///     horizontal-pass result clamped to 0...1 per premultiplied channel (issue #72, fitted to CI 39580013879: max 14 levels against 79/62/98 for the I2 bilinear; the residual is at alpha edges).
///     An enlarged or unchanged axis keeps the I2 triangle, and so does every image built by hand (`interpolates == false`, the I2 calibration cases).
/// Limits (measured and stated, not hidden): a source with an ODD side reduced by more than 2:1 is not reproduced (the Mac's mip chain for odd sizes was not identified; this
/// implementation drops the odd last row or column); `.high` at 1:1 smooths (the Mac does); exact nearest-neighbour ties (a pixel centre exactly on a source boundary) are decided by float noise on the Mac and are not pinned here.
public enum ImageResampler {
    /// Mitchell-Netravali (B, C) of the `.high` cubic. Fitted, see decision G53.
    public static let highCubic: (b: Double, c: Double) = (0.72, 0.12)

    public enum Filter: Equatable, Sendable {
        case nearest
        case triangle
        case cubic(b: Double, c: Double)
    }

    public struct Plan: Equatable, Sendable {
        public var filter: Filter
        /// Halve (2 x 2 box) while the reduction is MORE than 2:1 on both axes (exactly 2:1 is sampled directly: measured).
        public var mip: Bool
        /// Reducing axes use the interpolating-source downscale (`ImageResampler.reduction*`, issue #72); other axes use `filter`.
        public var interpolatedReduction: Bool
        public init(filter: Filter, mip: Bool, interpolatedReduction: Bool = false) { self.filter = filter; self.mip = mip; self.interpolatedReduction = interpolatedReduction }
    }

    /// Mitchell-Netravali (B, C) of the interpolating-source reduction: Catmull-Rom. Fitted, issue #72.
    public static let reductionCubic: (b: Double, c: Double) = (0, 0.5)

    /// The fitted plan for an `Image.Interpolation` level; nil (never set) draws like `.low`, as the Mac does, except that an `interpolates` source also reduces with `interpolatedReduction`.
    public static func plan(for level: Image.Interpolation?, interpolates: Bool = false) -> Plan {
        switch level {
        case .none?: return Plan(filter: .nearest, mip: false)
        case .low?: return Plan(filter: .triangle, mip: false)
        case nil: return Plan(filter: .triangle, mip: false, interpolatedReduction: interpolates)
        case .medium?: return Plan(filter: .triangle, mip: true)
        case .high?: return Plan(filter: .cubic(b: highCubic.b, c: highCubic.c), mip: true)
        }
    }

    /// Resamples `image` to `width` x `height` device pixels, the node's SNAPPED destination rect: the whole source is mapped onto it, so the sample scale is source / destination size
    /// (measured with fractional fit and fill frames: the unsnapped frame size is NOT the scale). An image drawn at its own size is returned as is.
    public static func resample(_ image: RGBAImage, width: Int, height: Int, level: Image.Interpolation?) -> RGBAImage {
        let plan = plan(for: level, interpolates: image.interpolates)
        let frameWidth = Double(width), frameHeight = Double(height)
        // At its own size nearest and bilinear are the identity, so the image is returned as is. `.high` is NOT: its cubic (B > 0) smooths at 1:1, and so does the Mac (measured: up to 112 levels on line art).
        if width == image.width && height == image.height {
            if case .cubic = plan.filter {} else { return image }
        }
        guard width > 0, height > 0, frameWidth > 0, frameHeight > 0 else { return image }
        var source = Buffer(image)
        if plan.mip {
            while Double(source.width) / frameWidth > 2, Double(source.height) / frameHeight > 2, source.width >= 2, source.height >= 2 { source = source.halved() }
        }
        let out: Buffer
        if plan.filter == .nearest {
            out = source.nearest(width: width, height: height, frameWidth: frameWidth, frameHeight: frameHeight)
        } else {
            let reduceX = plan.interpolatedReduction && source.width > width, reduceY = plan.interpolatedReduction && source.height > height
            let wx = reduceX ? reductionWeights(source: source.width, output: width) : weights(source: source.width, output: width, frame: frameWidth, filter: plan.filter)
            let wy = reduceY ? reductionWeights(source: source.height, output: height) : weights(source: source.height, output: height, frame: frameHeight, filter: plan.filter)
            out = source.filtered(wx, wy, width: width, height: height, clampPass: reduceX || reduceY)
        }
        return out.image()
    }

    // MARK: weights

    struct Taps { var first: Int; var weights: [Float] }

    static func kernel(_ filter: Filter, _ x: Double) -> Double {
        let a = abs(x)
        switch filter {
        case .nearest: return a < 0.5 ? 1 : 0
        case .triangle: return max(0, 1 - a)
        case .cubic(let b, let c):
            if a < 1 { return ((12 - 9 * b - 6 * c) * a * a * a + (-18 + 12 * b + 6 * c) * a * a + (6 - 2 * b)) / 6 }
            if a < 2 { return ((-b - 6 * c) * a * a * a + (6 * b + 30 * c) * a * a + (-12 * b - 48 * c) * a + (8 * b + 24 * c)) / 6 }
            return 0
        }
    }

    static func support(_ filter: Filter) -> Double {
        switch filter {
        case .nearest: return 0.5
        case .triangle: return 1
        case .cubic: return 2
        }
    }

    /// Point-sampled taps: output pixel t samples at c = (t + 0.5) * source / destination; the kernel is NOT widened by the reduction; the taps in range are renormalised.
    static func weights(source: Int, output: Int, frame: Double, filter: Filter) -> [Taps] {
        let s = Double(source) / frame
        let sup = support(filter)
        return (0..<output).map { t in
            let c = (Double(t) + 0.5) * s
            let lo = max(0, Int((c - sup).rounded(.down))), hi = min(source - 1, Int((c + sup).rounded(.up)))
            guard lo <= hi else { return Taps(first: min(max(0, Int(c.rounded(.down))), source - 1), weights: [1]) }
            var w = (lo...hi).map { kernel(filter, Double($0) + 0.5 - c) }
            let total = w.reduce(0, +)
            if abs(total) > 1e-12 { w = w.map { $0 / total } }
            return Taps(first: lo, weights: w.map { Float($0) })
        }
    }

    /// Interpolating-source reduction taps (issue #72): Catmull-Rom widened by the ratio, centres at t * (source - 1) / (output - 1) + 0.5 (the source centre for a single output pixel), taps in range renormalised.
    static func reductionWeights(source: Int, output: Int) -> [Taps] {
        let ratio = Double(source) / Double(output)
        let filter = Filter.cubic(b: reductionCubic.b, c: reductionCubic.c)
        let step = output > 1 ? Double(source - 1) / Double(output - 1) : 0
        let reach = support(filter) * ratio
        return (0..<output).map { t in
            let c = output > 1 ? Double(t) * step + 0.5 : Double(source) / 2
            let lo = max(0, Int((c - reach).rounded(.down))), hi = min(source - 1, Int((c + reach).rounded(.up)))
            guard lo <= hi else { return Taps(first: min(max(0, Int(c.rounded(.down))), source - 1), weights: [1]) }
            var w = (lo...hi).map { kernel(filter, (Double($0) + 0.5 - c) / ratio) }
            let total = w.reduce(0, +)
            if abs(total) > 1e-12 { w = w.map { $0 / total } }
            return Taps(first: lo, weights: w.map { Float($0) })
        }
    }

    // MARK: premultiplied buffer (r, g, b already multiplied by alpha; all in 0...1, gamma-encoded)

    struct Buffer {
        var width: Int, height: Int
        var p: [Float]   // width * height * 4: premultiplied r, g, b, alpha

        init(width: Int, height: Int, p: [Float]) { self.width = width; self.height = height; self.p = p }

        init(_ image: RGBAImage) {
            width = image.width; height = image.height
            p = [Float](repeating: 0, count: image.width * image.height * 4)
            for i in 0..<(image.width * image.height) {
                let a = Float(image.rgba[i * 4 + 3]) / 255
                p[i * 4] = Float(image.rgba[i * 4]) / 255 * a; p[i * 4 + 1] = Float(image.rgba[i * 4 + 1]) / 255 * a
                p[i * 4 + 2] = Float(image.rgba[i * 4 + 2]) / 255 * a; p[i * 4 + 3] = a
            }
        }

        /// 2 x 2 box average of premultiplied values; the result is quantised to straight 8-bit (as an image) and premultiplied again, as a mip level held in 8 bits.
        func halved() -> Buffer {
            let nw = width / 2, nh = height / 2
            var out = [Float](repeating: 0, count: nw * nh * 4)
            for y in 0..<nh {
                for x in 0..<nw {
                    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                    for dy in 0..<2 { for dx in 0..<2 {
                        let i = ((y * 2 + dy) * width + x * 2 + dx) * 4
                        r += p[i]; g += p[i + 1]; b += p[i + 2]; a += p[i + 3]
                    } }
                    r /= 4; g /= 4; b /= 4; a /= 4
                    let o = (y * nw + x) * 4
                    let a8 = (a * 255 + 0.5).rounded(.down)
                    if a > 1e-6 {
                        let r8 = min(255, max(0, (r / a * 255 + 0.5).rounded(.down))), g8 = min(255, max(0, (g / a * 255 + 0.5).rounded(.down))), b8 = min(255, max(0, (b / a * 255 + 0.5).rounded(.down)))
                        let af = a8 / 255
                        out[o] = r8 / 255 * af; out[o + 1] = g8 / 255 * af; out[o + 2] = b8 / 255 * af; out[o + 3] = af
                    }
                }
            }
            return Buffer(width: nw, height: nh, p: out)
        }

        func nearest(width w: Int, height h: Int, frameWidth: Double, frameHeight: Double) -> Buffer {
            var out = [Float](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                let sy = min(height - 1, max(0, Int(((Double(y) + 0.5) * Double(height) / frameHeight).rounded(.down))))
                for x in 0..<w {
                    let sx = min(width - 1, max(0, Int(((Double(x) + 0.5) * Double(width) / frameWidth).rounded(.down))))
                    let i = (sy * width + sx) * 4, o = (y * w + x) * 4
                    out[o] = p[i]; out[o + 1] = p[i + 1]; out[o + 2] = p[i + 2]; out[o + 3] = p[i + 3]
                }
            }
            return Buffer(width: w, height: h, p: out)
        }

        /// `clampPass`: the horizontal-pass result is clamped to 0...1 per channel before the vertical pass (the Mac's 8-bit intermediate; only the interpolating-source reduction uses it).
        func filtered(_ wx: [Taps], _ wy: [Taps], width w: Int, height h: Int, clampPass: Bool = false) -> Buffer {
            var mid = [Float](repeating: 0, count: height * w * 4)   // horizontal pass
            for y in 0..<height {
                for x in 0..<w {
                    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                    let taps = wx[x]
                    for (k, weight) in taps.weights.enumerated() {
                        let i = (y * width + taps.first + k) * 4
                        r += p[i] * weight; g += p[i + 1] * weight; b += p[i + 2] * weight; a += p[i + 3] * weight
                    }
                    let o = (y * w + x) * 4
                    if clampPass { r = min(1, max(0, r)); g = min(1, max(0, g)); b = min(1, max(0, b)); a = min(1, max(0, a)) }
                    mid[o] = r; mid[o + 1] = g; mid[o + 2] = b; mid[o + 3] = a
                }
            }
            var out = [Float](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                let taps = wy[y]
                for x in 0..<w {
                    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                    for (k, weight) in taps.weights.enumerated() {
                        let i = ((taps.first + k) * w + x) * 4
                        r += mid[i] * weight; g += mid[i + 1] * weight; b += mid[i + 2] * weight; a += mid[i + 3] * weight
                    }
                    let o = (y * w + x) * 4
                    out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a
                }
            }
            return Buffer(width: w, height: h, p: out)
        }

        /// Straight 8-bit RGBA; a pixel of alpha 0 has RGB 0 (nothing bleeds).
        func image() -> RGBAImage {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for i in 0..<(width * height) {
                let a = min(1, max(0, p[i * 4 + 3]))
                guard a > 1e-6 else { continue }
                func byte(_ v: Float) -> UInt8 { UInt8(min(255, max(0, (min(1, max(0, v)) * 255 + 0.5).rounded(.down)))) }
                bytes[i * 4] = byte(p[i * 4] / a); bytes[i * 4 + 1] = byte(p[i * 4 + 1] / a); bytes[i * 4 + 2] = byte(p[i * 4 + 2] / a); bytes[i * 4 + 3] = byte(a)
            }
            return RGBAImage(width: width, height: height, rgba: bytes)!
        }
    }
}
