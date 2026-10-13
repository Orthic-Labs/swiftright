import Foundation

/// SF Symbol LAYOUT metrics (never outlines), measured on a Mac at mapping-table build time by
/// `factory/tools/symbol-metrics`. A resizable, scaled-to-fit symbol occupies a layout box of
/// `aspect` (width / height) fitted and centred in its frame; the symbol's ink (half-coverage
/// bounding box) sits at the given fractions of that box. A substitute glyph is scaled and placed
/// so its own ink box lands on exactly the same rectangle.
public struct SystemImageLayoutMetrics: Equatable, Sendable {
    /// Layout box width / height.
    public let aspect: Double
    /// Ink box as fractions of the layout box, top-down: left, top, right, bottom.
    public let inkLeft: Double
    public let inkTop: Double
    public let inkRight: Double
    public let inkBottom: Double
    /// Pixel bias per edge (left, top, right, bottom) of the half-coverage ink box: the box edge in whole
    /// pixels is `floor(fraction * viewPixels + bias)`. 0.5 is plain rounding; fitted values absorb how
    /// pointed glyph tips cover pixels (see `predictedInkBox`).
    public let inkBias: [Double]

    public init(aspect: Double, inkLeft: Double, inkTop: Double, inkRight: Double, inkBottom: Double,
                inkBias: [Double] = [0.5, 0.5, 0.5, 0.5]) {
        self.aspect = aspect
        self.inkLeft = inkLeft
        self.inkTop = inkTop
        self.inkRight = inkRight
        self.inkBottom = inkBottom
        self.inkBias = inkBias.count == 4 ? inkBias : [0.5, 0.5, 0.5, 0.5]
    }

    /// Half-coverage ink box in whole pixels, relative to the pixel-snapped Image view frame of
    /// `widthPx` x `heightPx`, for ANY frame size: SwiftUI's symbol box aspect depends only on the screen-scale
    /// class (`aspect` here is that class's fit intrinsic ratio), and the ink edges scale with the view frame.
    /// Measured against SwiftUI on 120 held-out frames this reproduces the whole box exactly for about 80% of
    /// frames and every edge to within one pixel; the remainder depend on the sub-pixel phase of sharp tips,
    /// which needs the outline and is therefore not modelled (docs/sr1-decisions.md item 3).
    public func predictedInkBox(widthPx: Int, heightPx: Int) -> SystemImageDeviceInkBox? {
        guard widthPx > 0, heightPx > 0 else { return nil }
        let w = Double(widthPx), h = Double(heightPx)
        let box = SystemImageDeviceInkBox(left: Int((inkLeft * w + inkBias[0]).rounded(.down)),
                                          top: Int((inkTop * h + inkBias[1]).rounded(.down)),
                                          right: Int((inkRight * w + inkBias[2]).rounded(.down)),
                                          bottom: Int((inkBottom * h + inkBias[3]).rounded(.down)))
        return box.isValid ? box : nil
    }

    /// Ink may overflow the layout box slightly (negative or >1 fractions), never wildly.
    public var isValid: Bool {
        let fractions = [inkLeft, inkTop, inkRight, inkBottom]
        return aspect.isFinite && aspect > 0 && fractions.allSatisfy { $0.isFinite && $0 >= -0.25 && $0 <= 1.25 }
            && inkRight > inkLeft && inkBottom > inkTop
    }
}

/// Fractional rectangle in target pixels, top-down.
public struct SystemImageFitRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Half-coverage ink bounding box in whole target pixels relative to the frame origin (right and bottom
/// exclusive; may extend past the frame, symbols overflow their frames by a pixel or two), measured on the Mac for one device configuration (frame size in points and screen scale).
/// SwiftUI quantises symbol boxes to device pixels, so the ink box at a given scale is not a pure linear
/// function of the frame; the pixel box is the authoritative placement when a calibration exists.
public struct SystemImageDeviceInkBox: Equatable, Sendable {
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public var isValid: Bool { right > left && bottom > top }
}

public struct SystemImageAlignedRaster: Sendable {
    public let raster: SystemImageRasterOutput
    /// Where the glyph's ink was placed (fractional target pixels).
    public let inkRect: SystemImageFitRect
    /// Half-coverage (alpha >= 128) pixel bounding box actually produced.
    public let halfCoverageBox: SystemImageDeviceInkBox
    /// With a device calibration: whether the produced box equals it exactly. Nil without one.
    /// (`inkRect` and `halfCoverageBox` are relative to the frame origin; `raster` is the inset canvas.)
    public let deviceInkMatched: Bool?
}

public enum SystemImageFit {
    /// Aspect-fit (never up-distorting), centred layout box of a symbol inside its frame.
    public static func layoutBox(aspect: Double, targetWidth: Double, targetHeight: Double) -> SystemImageFitRect {
        let height = min(targetWidth / aspect, targetHeight)
        let width = height * aspect
        return SystemImageFitRect(x: (targetWidth - width) / 2, y: (targetHeight - height) / 2,
                                  width: width, height: height)
    }

    /// Where the symbol's ink lands inside the frame.
    public static func inkRect(_ metrics: SystemImageLayoutMetrics,
                               targetWidth: Double, targetHeight: Double) -> SystemImageFitRect {
        let box = layoutBox(aspect: metrics.aspect, targetWidth: targetWidth, targetHeight: targetHeight)
        return SystemImageFitRect(x: box.x + metrics.inkLeft * box.width,
                                  y: box.y + metrics.inkTop * box.height,
                                  width: (metrics.inkRight - metrics.inkLeft) * box.width,
                                  height: (metrics.inkBottom - metrics.inkTop) * box.height)
    }

    /// Half-coverage bounding box of a coverage bitmap in source pixels (whole-pixel edges, so the
    /// source should be oversampled relative to the target; the hosts request 8x). Lines whose peak
    /// coverage is below half are outside the ink, which excludes the faint tips of sharp glyphs
    /// exactly as the Mac-side measurement does.
    public static func halfCoverageBounds(coverage: [UInt8], rowBytes: Int, width: Int, height: Int,
                                          rowOrder: SystemImageRasterRowOrder,
                                          coverageMaximum: UInt8) -> SystemImageFitRect? {
        guard width > 0, height > 0, rowBytes >= width, coverage.count >= rowBytes * height,
              coverageMaximum > 0 else { return nil }
        let half = (Double(coverageMaximum) / 2).rounded(.up)
        var colHit = [Bool](repeating: false, count: width)
        var rowHit = [Bool](repeating: false, count: height)
        for y in 0..<height {
            let row = rowOrder == .topDown ? y : height - 1 - y
            for x in 0..<width where Double(coverage[row * rowBytes + x]) >= half {
                colHit[x] = true
                rowHit[y] = true
            }
        }
        guard let x0 = colHit.firstIndex(of: true), let x1 = colHit.lastIndex(of: true),
              let y0 = rowHit.firstIndex(of: true), let y1 = rowHit.lastIndex(of: true) else { return nil }
        return SystemImageFitRect(x: Double(x0), y: Double(y0),
                                  width: Double(x1 + 1 - x0), height: Double(y1 + 1 - y0))
    }
}

extension SystemImageRasterProvider {
    /// Composes a substitute glyph so its half-coverage ink box lands on the symbol's ink rectangle
    /// inside the frame: `deviceInk` (Mac pixel box for this scale and frame) when given, else the linear
    /// `SystemImageFit.inkRect(metrics)`. The coverage bitmap is forward-mapped with exact area weighting,
    /// so edges carry true fractional coverage. The glyph is scaled independently in x and y: frame,
    /// aspect-fit and ink bounds match the Mac symbol while the glyph shape remains the provider's own.
    /// With `deviceInk`, the placement is refined in 1/16 pixel steps until the produced pixel-level
    /// half-coverage box equals the Mac box (sharp glyph tips cover under half a pixel at the extremes,
    /// so the nominal rectangle alone can land a pixel short); a failure to converge is reported, not hidden.
    public static func composeAligned(_ input: SystemImageRasterInput,
                                      metrics: SystemImageLayoutMetrics,
                                      deviceInk: SystemImageDeviceInkBox? = nil,
                                      targetWidth frameWidth: UInt32,
                                      targetHeight frameHeight: UInt32,
                                      inset: UInt32 = 0,
                                      tintRGBA: UInt32) throws -> SystemImageAlignedRaster {
        // The canvas is the frame grown by `inset` px on every side so ink that overflows the frame is kept.
        // Metrics, device boxes and the reported ink rect/box are all relative to the FRAME origin.
        guard inset <= 64 else { throw SystemImageRasterError.invalidDimensions }
        let targetWidth = frameWidth + 2 * inset, targetHeight = frameHeight + 2 * inset
        let pad = Double(inset)
        guard metrics.isValid, deviceInk?.isValid ?? true, input.sourceWidth > 0, input.sourceHeight > 0,
              input.rowBytes >= input.sourceWidth, input.coverageMaximum > 0,
              targetWidth > 0, targetHeight > 0 else {
            throw SystemImageRasterError.invalidDimensions
        }
        guard input.sourceWidth <= 4096, input.sourceHeight <= 4096,
              targetWidth <= 4096, targetHeight <= 4096 else {
            throw SystemImageRasterError.targetTooLarge
        }
        if let d = deviceInk, d.left < -Int(inset) || d.top < -Int(inset)
            || d.right > Int(frameWidth + inset) || d.bottom > Int(frameHeight + inset) {
            throw SystemImageRasterError.invalidDimensions
        }
        let sourceBytes = UInt64(input.rowBytes) * UInt64(input.sourceHeight)
        let targetBytes = UInt64(targetWidth) * UInt64(targetHeight) * 4
        guard sourceBytes <= 16 * 1024 * 1024, sourceBytes <= UInt64(input.coverage.count),
              targetBytes <= 16 * 1024 * 1024 else {
            throw SystemImageRasterError.invalidCoverage
        }
        func face(_ value: String) -> String {
            guard let end = value.firstIndex(of: "\0") else { return value }
            return String(value[..<end])
        }
        guard face(input.selectedFace) == face(input.expectedFace), !face(input.expectedFace).isEmpty else {
            throw SystemImageRasterError.selectedFaceMismatch
        }
        guard let src = SystemImageFit.halfCoverageBounds(
            coverage: input.coverage, rowBytes: Int(input.rowBytes), width: Int(input.sourceWidth),
            height: Int(input.sourceHeight), rowOrder: input.rowOrder,
            coverageMaximum: input.coverageMaximum) else {
            throw SystemImageRasterError.emptyCoverage
        }
        let tw = Int(targetWidth), th = Int(targetHeight)
        // Source samples with coverage, row-resolved once.
        let sw = Int(input.sourceWidth), sh = Int(input.sourceHeight), stride = Int(input.rowBytes)
        let maxCov = Float(input.coverageMaximum)
        var samples: [(x: Int32, y: Int32, c: Float)] = []
        samples.reserveCapacity(sw * sh / 2)
        for sy in 0..<sh {
            let row = input.rowOrder == .topDown ? sy : sh - 1 - sy
            for sx in 0..<sw {
                let v = input.coverage[row * stride + sx]
                if v > 0 { samples.append((Int32(sx), Int32(sy), Float(min(v, input.coverageMaximum)) / maxCov)) }
            }
        }
        func accumulate(_ rect: SystemImageFitRect) -> [Float] {
            let kx = rect.width / src.width, ky = rect.height / src.height
            var accum = [Float](repeating: 0, count: tw * th)
            for s in samples {
                let a0 = rect.x + (Double(s.x) - src.x) * kx, a1 = a0 + kx
                let b0 = rect.y + (Double(s.y) - src.y) * ky, b1 = b0 + ky
                guard a1 > 0, a0 < Double(tw), b1 > 0, b0 < Double(th) else { continue }
                let ix0 = max(0, Int(a0.rounded(.down))), ix1 = min(tw - 1, Int((a1 - 1e-12).rounded(.down)))
                let iy0 = max(0, Int(b0.rounded(.down))), iy1 = min(th - 1, Int((b1 - 1e-12).rounded(.down)))
                guard ix0 <= ix1, iy0 <= iy1 else { continue }
                for ty in iy0...iy1 {
                    let oy = min(b1, Double(ty + 1)) - max(b0, Double(ty))
                    for tx in ix0...ix1 {
                        let ox = min(a1, Double(tx + 1)) - max(a0, Double(tx))
                        accum[ty * tw + tx] += s.c * Float(ox * oy)
                    }
                }
            }
            return accum
        }
        func coverageByte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        func halfBox(_ accum: [Float]) -> SystemImageDeviceInkBox? {
            var x0 = tw, y0 = th, x1 = -1, y1 = -1
            for ty in 0..<th { for tx in 0..<tw where coverageByte(accum[ty * tw + tx]) >= 128 {
                x0 = min(x0, tx); x1 = max(x1, tx); y0 = min(y0, ty); y1 = max(y1, ty) } }
            return x1 < 0 ? nil : SystemImageDeviceInkBox(left: x0, top: y0, right: x1 + 1, bottom: y1 + 1)
        }

        var rect: SystemImageFitRect
        if let d = deviceInk {
            rect = SystemImageFitRect(x: Double(d.left) + pad, y: Double(d.top) + pad,
                                      width: Double(d.right - d.left), height: Double(d.bottom - d.top))
        } else {
            let r = SystemImageFit.inkRect(metrics, targetWidth: Double(frameWidth), targetHeight: Double(frameHeight))
            rect = SystemImageFitRect(x: r.x + pad, y: r.y + pad, width: r.width, height: r.height)
        }
        var accum = accumulate(rect)
        var produced = halfBox(accum)
        if let d = deviceInk {
            // closed-loop refinement of each edge in 1/16 px steps (bounded)
            let step = 1.0 / 16, limit = 2.0
            let nominal = rect
            let dc = SystemImageDeviceInkBox(left: d.left + Int(inset), top: d.top + Int(inset),
                                             right: d.right + Int(inset), bottom: d.bottom + Int(inset))
            var best = (rect, accum, produced, Int.max)
            func error(_ b: SystemImageDeviceInkBox?) -> Int {
                guard let b else { return Int.max / 2 }
                return abs(b.left - dc.left) + abs(b.top - dc.top) + abs(b.right - dc.right) + abs(b.bottom - dc.bottom)
            }
            best.3 = error(produced)
            var iterations = 0
            while let b = produced, error(b) != 0, iterations < 64 {
                iterations += 1
                var x0 = rect.x, y0 = rect.y, x1 = rect.x + rect.width, y1 = rect.y + rect.height
                if b.left > dc.left { x0 -= step } else if b.left < dc.left { x0 += step }
                if b.top > dc.top { y0 -= step } else if b.top < dc.top { y0 += step }
                if b.right < dc.right { x1 += step } else if b.right > dc.right { x1 -= step }
                if b.bottom < dc.bottom { y1 += step } else if b.bottom > dc.bottom { y1 -= step }
                guard x1 - x0 > step, y1 - y0 > step,
                      abs(x0 - nominal.x) <= limit, abs(y0 - nominal.y) <= limit,
                      abs(x1 - (nominal.x + nominal.width)) <= limit, abs(y1 - (nominal.y + nominal.height)) <= limit else { break }
                rect = SystemImageFitRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                accum = accumulate(rect)
                produced = halfBox(accum)
                let e = error(produced)
                if e < best.3 { best = (rect, accum, produced, e) }
            }
            if best.3 < error(produced) { rect = best.0; accum = best.1; produced = best.2 }
        }

        var rgba = [UInt8](repeating: 0, count: Int(targetBytes))
        let red = UInt8((tintRGBA >> 24) & 0xff), green = UInt8((tintRGBA >> 16) & 0xff)
        let blue = UInt8((tintRGBA >> 8) & 0xff), tintAlpha = UInt32(tintRGBA & 0xff)
        var nonZero: UInt32 = 0
        var maximum: UInt8 = 0
        var minX = tw, minY = th, maxX = -1, maxY = -1
        for ty in 0..<th {
            for tx in 0..<tw {
                let coverage = coverageByte(accum[ty * tw + tx])
                guard coverage > 0 else { continue }
                nonZero += 1
                maximum = max(maximum, coverage)
                minX = min(minX, tx); maxX = max(maxX, tx); minY = min(minY, ty); maxY = max(maxY, ty)
                let index = (ty * tw + tx) * 4
                rgba[index] = red; rgba[index + 1] = green; rgba[index + 2] = blue
                rgba[index + 3] = UInt8((UInt32(coverage) * tintAlpha + 127) / 255)
            }
        }
        guard nonZero > 0, let box = produced else { throw SystemImageRasterError.emptyCoverage }
        let output = SystemImageRasterOutput(rgba: rgba, width: targetWidth, height: targetHeight,
                                             renderedWidth: UInt32(maxX - minX + 1), renderedHeight: UInt32(maxY - minY + 1),
                                             nonZeroCoverage: nonZero, maxCoverage: maximum)
        let frameBox = SystemImageDeviceInkBox(left: box.left - Int(inset), top: box.top - Int(inset),
                                               right: box.right - Int(inset), bottom: box.bottom - Int(inset))
        return SystemImageAlignedRaster(raster: output,
                                        inkRect: SystemImageFitRect(x: rect.x - pad, y: rect.y - pad, width: rect.width, height: rect.height),
                                        halfCoverageBox: frameBox, deviceInkMatched: deviceInk.map { $0 == frameBox })
    }

    public static func composeMetricsAligned(_ input: SystemImageRasterInput,
                                             metrics: SystemImageLayoutMetrics,
                                             targetWidth: UInt32,
                                             targetHeight: UInt32,
                                             tintRGBA: UInt32) throws -> SystemImageRasterOutput {
        try composeAligned(input, metrics: metrics, targetWidth: targetWidth,
                           targetHeight: targetHeight, tintRGBA: tintRGBA).raster
    }
}
