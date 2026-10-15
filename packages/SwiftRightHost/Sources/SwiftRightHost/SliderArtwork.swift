import Foundation
import SwiftRightRuntime

/// Our own model of SwiftUI's macOS Slider (decision H4): a 14 px capsule track, an accent fill up to the value, and a 50 x 40 px thumb (20 x 16 pt at
/// scale 2.5) with a soft shadow. Windows has no SF slider artwork and Apple's is not redistributable, so the slider is drawn from planes and tables measured
/// on SwiftUI renders (`factory/tools/switch-artwork/derive_slider_profile.py` produces `SliderArtworkData`).
///
/// Per pixel, over any background (premultiplied; m = thumb mask, s = its shadow, a = body alpha: 1 light, 217/255 dark, track layer Pt/at):
///     alpha  = 1 - (1 - a m)(1 - s)(1 - at (1 - h))          h = m for a translucent (dark) body, 0 for an opaque one
///     colour = 255 a m + (1 - a m)(1 - s)(1 - h) Pt
/// The track is black (white in dark) at alpha 25/255; the fill is the accent colour, or, disabled, black (white) at alpha 37/255 (36/255) in place of the track.
/// Exact at scale 2.5 (<= 1 level but 4 at the end caps); another scale resamples the planes bilinearly (not pixel-gated).
public enum SliderArtwork {
    public static let referenceScale: Float = 2.5

    struct Planes {
        let mask: [Double]      // 50 x 40
        let shadow: [Double]    // (50 + 32) x (40 + 32)
        let bodyAlpha: Double
        let accent: (Double, Double, Double)
        let disabledAlpha: Double
        let trackColour: Double // 0 (black) or 255 (white)
    }

    private static func decode16(_ b64: String, count: Int) -> [Double] {
        guard let data = Data(base64Encoded: b64), data.count == count * 2 else { return [Double](repeating: 0, count: count) }
        var out = [Double](repeating: 0, count: count)
        data.withUnsafeBytes { raw in for i in 0..<count { out[i] = Double(UInt16(raw[2 * i]) | UInt16(raw[2 * i + 1]) << 8) / 4095 } }
        return out
    }

    private static func decode8(_ b64: String, count: Int) -> [Double] {
        guard let data = Data(base64Encoded: b64), data.count == count else { return [Double](repeating: 0, count: count) }
        return data.map { Double($0) / 255 }
    }

    private static let m = SliderArtworkData.shadowMarginPX, tw = SliderArtworkData.thumbWidthPX, th = SliderArtworkData.thumbHeightPX
    private static let light = Planes(mask: decode16(SliderArtworkData.lightMask, count: tw * th), shadow: decode16(SliderArtworkData.lightShadow, count: (tw + 2 * m) * (th + 2 * m)),
                                      bodyAlpha: SliderArtworkData.lightBodyAlpha, accent: SliderArtworkData.lightAccent, disabledAlpha: SliderArtworkData.lightDisabledFillAlpha, trackColour: 0)
    private static let dark = Planes(mask: decode16(SliderArtworkData.darkMask, count: tw * th), shadow: decode16(SliderArtworkData.darkShadow, count: (tw + 2 * m) * (th + 2 * m)),
                                     bodyAlpha: SliderArtworkData.darkBodyAlpha, accent: SliderArtworkData.darkAccent, disabledAlpha: SliderArtworkData.darkDisabledFillAlpha, trackColour: 255)
    private static let capEmpty = decode8(SliderArtworkData.capEmpty, count: 14 * 8)
    private static let capFill = decode8(SliderArtworkData.capFill, count: 14 * 8)

    private struct Key: Hashable { let w: Int, h: Int, thumb: Int, fill: Int, enabled: Bool, dark: Bool, scale: Int }
    nonisolated(unsafe) private static var cache: [Key: ContinuousRGBAImage] = [:]
    private static let cacheLock = NSLock()

    /// Margin around the control the image extends by (the thumb's shadow), in device pixels, at `scale`.
    public static func marginPX(scale: Float) -> Int { Int((Double(m) * Double(scale / referenceScale)).rounded(.up)) }

    /// The thumb's size in device pixels at `scale`.
    public static func thumbPX(scale: Float) -> (width: Int, height: Int) {
        (Int((Double(scale) * 20).rounded()), Int((Double(scale) * 16).rounded()))
    }

    /// Straight-alpha RGBA of the control: `(widthPX + 2 margin) x (heightPX + 2 margin)`, the control's frame sitting `margin` px in from the top left.
    /// `thumbOffsetPX`: the thumb's left edge from the track's left edge; `fillEndPX`: where the fill ends (`fraction * widthPX`).
    public static func render(widthPX: Int, heightPX: Int, thumbOffsetPX: Int, fillEndPX: Double, isEnabled: Bool, scheme: ColorScheme, scale: Float = referenceScale) -> ContinuousRGBAImage {
        let key = Key(w: widthPX, h: heightPX, thumb: thumbOffsetPX, fill: Int((fillEndPX * 8).rounded()), enabled: isEnabled, dark: scheme == .dark, scale: Int((scale * 100).rounded()))
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        if cache.count > 64 { cache.removeAll() }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, thumbOffsetPX: thumbOffsetPX, fillEndPX: fillEndPX, isEnabled: isEnabled, planes: scheme == .dark ? dark : light, scale: scale)
        cache[key] = image
        return image
    }

    /// Bilinear sample of a row-major plane of `w x h` at (x, y) in plane pixel coordinates (pixel centres at +0.5), zero outside.
    private static func sample(_ plane: [Double], _ w: Int, _ h: Int, _ x: Double, _ y: Double) -> Double {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        func at(_ xi: Int, _ yi: Int) -> Double { xi >= 0 && xi < w && yi >= 0 && yi < h ? plane[yi * w + xi] : 0 }
        return (at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx) * (1 - ty) + (at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx) * ty
    }

    private static func rasterize(widthPX: Int, heightPX: Int, thumbOffsetPX: Int, fillEndPX: Double, isEnabled: Bool, planes: Planes, scale: Float) -> ContinuousRGBAImage {
        let k = Double(scale / referenceScale)
        let exact = abs(k - 1) < 1e-6
        let margin = marginPX(scale: scale)
        let outW = widthPX + 2 * margin, outH = heightPX + 2 * margin
        let (thumbW, thumbH) = thumbPX(scale: scale)
        let trackH = exact ? SliderArtworkData.trackHeightPX : max(1, Int((14 * k).rounded()))
        let trackTop = (heightPX - trackH) / 2
        let thumbTop = (heightPX - thumbH) / 2
        let a = planes.bodyAlpha
        let translucent = a < 1
        let accent = planes.accent
        let A = SliderArtworkData.trackAlpha
        var rgba = [UInt8](repeating: 0, count: outW * outH * 4)

        func cap(_ table: [Double], _ x: Int, _ j: Int) -> Double {
            let capCols = exact ? 8 : max(1, Int((8 * k).rounded()))
            let col: Int
            if x < capCols { col = x } else if x >= widthPX - capCols { col = widthPX - 1 - x } else { return 1 }
            if exact { return table[j * 8 + col] }
            return sample(table, 8, 14, (Double(col) + 0.5) / k, (Double(j) + 0.5) / k)
        }

        for y in -margin..<(heightPX + margin) {
            for x in -margin..<(widthPX + margin) {
                // track layers
                var pt = 0.0, at = 0.0          // premultiplied track colour (one grey channel for the empty track), alpha
                var ptRGB = (0.0, 0.0, 0.0)
                let j = y - trackTop
                if j >= 0, j < trackH, x >= 0, x < widthPX {
                    let ce = cap(capEmpty, x, j)
                    at = A * ce
                    pt = planes.trackColour * at
                    ptRGB = (pt, pt, pt)
                    if Double(x) < fillEndPX {
                        let cf = cap(capFill, x, j)
                        if isEnabled {
                            ptRGB = (accent.0 * cf + ptRGB.0 * (1 - cf), accent.1 * cf + ptRGB.1 * (1 - cf), accent.2 * cf + ptRGB.2 * (1 - cf))
                            at = cf + at * (1 - cf)
                        } else {
                            let af = planes.disabledAlpha * cf
                            let g = planes.trackColour * af
                            ptRGB = (g, g, g); at = af
                        }
                    }
                }
                // thumb
                let i = x - thumbOffsetPX, jj = y - thumbTop
                var mask = 0.0, shadow = 0.0
                if exact {
                    if i >= 0, i < tw, jj >= 0, jj < th { mask = planes.mask[jj * tw + i] }
                    let si = i + m, sj = jj + m
                    if si >= 0, si < tw + 2 * m, sj >= 0, sj < th + 2 * m { shadow = planes.shadow[sj * (tw + 2 * m) + si] }
                } else {
                    let u = (Double(i) + 0.5) / k, v = (Double(jj) + 0.5) / k
                    mask = sample(planes.mask, tw, th, u, v)
                    shadow = sample(planes.shadow, tw + 2 * m, th + 2 * m, u + Double(m), v + Double(m))
                }
                let hole = translucent ? mask : 0
                let transmit = (1 - a * mask) * (1 - shadow)
                let alpha = 1 - transmit * (1 - at * (1 - hole))
                guard alpha > 0 else { continue }
                let keep = transmit * (1 - hole)
                let body = 255 * a * mask
                let alpha8 = max(0, min(255, (alpha * 255).rounded()))
                guard alpha8 > 0 else { continue }
                let o = ((y + margin) * outW + (x + margin)) * 4
                let premult = [body + keep * ptRGB.0, body + keep * ptRGB.1, body + keep * ptRGB.2]
                for c in 0..<3 { rgba[o + c] = UInt8(max(0, min(255, (premult[c] / (alpha8 / 255)).rounded()))) }
                rgba[o + 3] = UInt8(alpha8)
            }
        }
        return ContinuousRGBAImage(width: outW, height: outH, rgba: rgba)
    }
}

/// How one Slider node is painted: the control's artwork (registered as an image, like the Toggle's) and the facts the accessibility tree needs.
public struct SliderPaintPlan {
    public var image: ContinuousRGBAImage
    /// Where the image goes (pixels, window coordinates), the control's frame grown by the shadow margin.
    public var placement: Rect
    public var isEnabled: Bool
    public var value: Double
    public var lower: Double, upper: Double
    public var smallChange: Double, largeChange: Double
    public var isFocused: Bool
}

public enum SliderPainter {
    /// `bounds` is the node's pixel frame in window coordinates (the host's placement applied); the control sits inside it where `ResolvedSlider.trackPixelFrame` says.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> SliderPaintPlan {
        guard let slider = node.slider else { throw HostPaintError.sliderMetadataRequired }
        guard node.opacity == 1, node.style.foreground == nil else { throw HostPaintError.unsupportedSliderPaintStyle }
        let track = slider.trackPixelFrame
        let width = Int(track.width), height = Int(track.height)
        guard width > 0, height > 0 else { throw HostPaintError.sliderMetadataRequired }
        let dx = bounds.x - Float(node.pixelFrame.x), dy = bounds.y - Float(node.pixelFrame.y)
        let margin = SliderArtwork.marginPX(scale: scale)
        let image = SliderArtwork.render(widthPX: width, heightPX: height, thumbOffsetPX: slider.thumbOffsetPixels, fillEndPX: slider.fraction * Double(width),
                                         isEnabled: node.accessibility.isEnabled, scheme: node.style.colorScheme, scale: scale)
        return SliderPaintPlan(image: image,
                               placement: Rect(x: Float(track.x) + dx - Float(margin) + imageGuardBand, y: Float(track.y) + dy - Float(margin) + imageGuardBand,
                                               w: Float(image.width) - 2 * imageGuardBand, h: Float(image.height) - 2 * imageGuardBand),
                               isEnabled: node.accessibility.isEnabled, value: slider.value, lower: slider.lower, upper: slider.upper,
                               smallChange: slider.smallChange, largeChange: slider.largeChange, isFocused: slider.isFocused)
    }
}
