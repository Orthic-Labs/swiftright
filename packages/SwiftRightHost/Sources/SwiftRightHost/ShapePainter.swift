import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// A continuous-corner shape to rasterise: pixel bounds (window coordinates), corner radius and stroke in pixels.
public struct ContinuousShapeRequest: Equatable {
    public var bounds: Rect
    public var cornerRadiusPX: Float
    public var fillRGBA: UInt32?
    public var strokeRGBA: UInt32?
    public var strokeWidthPX: Float
    /// Device pixels per point: the unit `bounds` edges are snapped in (`DevicePixelSnap`).
    public var scale: Float
    public init(bounds: Rect, cornerRadiusPX: Float, fillRGBA: UInt32?, strokeRGBA: UInt32?, strokeWidthPX: Float, scale: Float = 1) {
        self.bounds = bounds; self.cornerRadiusPX = cornerRadiusPX; self.fillRGBA = fillRGBA
        self.strokeRGBA = strokeRGBA; self.strokeWidthPX = strokeWidthPX; self.scale = scale
    }
}

/// How one shape node is painted: a plain ABI rect (rectangle, circle, circular rounded rectangle) or a continuous
/// corner shape rasterised on the host side and registered as an image (the ABI has no continuous-corner primitive).
public enum ShapePaintPlan {
    case primitive(Primitive)
    case continuous(ContinuousShapeRequest)
}

public enum ShapePainter {
    /// Resolves a Rectangle / RoundedRectangle / Circle node to its paint, from runtime geometry and paint only.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> ShapePaintPlan {
        guard let shape = node.shape, let paint = shape.paint else { throw HostPaintError.shapeMetadataRequired }
        let colour = try HostPaint.rgba(paint.color, opacity: node.opacity, scheme: node.style.colorScheme)
        var strokeWidth: Float = 0
        if paint.kind == .stroke {
            guard let logical = paint.lineWidth, logical.isFinite, logical >= 0 else { throw HostPaintError.shapeStrokeWidthRequired }
            strokeWidth = Float(logical) * scale
            guard strokeWidth.isFinite else { throw HostPaintError.invalidScaledStrokeWidth }
        }
        var frame = bounds
        var radius: Float = 0
        switch shape.geometry {
        case .rectangle:
            break
        case .circle:
            // A circle is the largest centred square of its frame.
            let diameter = min(bounds.w, bounds.h)
            frame = Rect(x: bounds.x + (bounds.w - diameter) / 2, y: bounds.y + (bounds.h - diameter) / 2, w: diameter, h: diameter)
            radius = diameter / 2
        case .roundedRectangle(let cornerRadius, let style):
            switch style {
            case .circular:
                radius = min(Float(cornerRadius) * scale, min(bounds.w, bounds.h) / 2)
            case .continuous:
                let request = ContinuousShapeRequest(
                    bounds: bounds, cornerRadiusPX: Float(cornerRadius) * scale,
                    fillRGBA: paint.kind == .fill ? colour : nil,
                    strokeRGBA: paint.kind == .stroke ? colour : nil,
                    strokeWidthPX: strokeWidth, scale: scale)
                return .continuous(request)
            }
        }
        switch paint.kind {
        case .fill:
            return .primitive(.rect(frame, color: colour, radius: radius))
        case .stroke:
            // A stroke is centred on the path: the ABI border sits inside its rect, so grow the rect and radius by half the width.
            let half = strokeWidth / 2
            let stroked = Rect(x: frame.x - half, y: frame.y - half, w: frame.w + strokeWidth, h: frame.h + strokeWidth)
            let strokedRadius = radius == 0 ? 0 : min(radius + half, min(stroked.w, stroked.h) / 2)
            return .primitive(.rect(stroked, color: 0, radius: strokedRadius, borderColor: colour, borderWidth: strokeWidth))
        }
    }
}

public enum ContinuousShapeRaster {
    /// The raster of one continuous shape: the bitmap and where it is placed (pixels). Pure; no renderer involved.
    public struct Result: Equatable {
        public var image: ContinuousRGBAImage
        public var placement: Rect
    }

    /// Where a continuous shape's bitmap goes and how large it is: the snapped bounds, the integer origin at or before the stroked outer edge, the fractional remainder
    /// baked into the bitmap, and the bitmap's size. Pure geometry, no raster.
    struct Layout {
        var originX: Float, originY: Float, fracX: Double, fracY: Double, boundsW: Float, boundsH: Float, width: Int, height: Int
    }

    static func layout(_ request: ContinuousShapeRequest) throws -> Layout {
        guard request.bounds.w.isFinite, request.bounds.h.isFinite,
              request.bounds.w > 0, request.bounds.h > 0,
              request.cornerRadiusPX.isFinite, request.cornerRadiusPX >= 0,
              request.strokeWidthPX.isFinite, request.strokeWidthPX >= 0 else {
            throw HostPaintError.continuousShapeRasterInput(1)
        }
        // SwiftUI draws a frame on whole device pixels (both edges rounded; DevicePixelSnap), so the path
        // rectangle is the snapped one, never the fractional layout rectangle.
        let snapX = DevicePixelSnap.edges(origin: Double(request.bounds.x), length: Double(request.bounds.w), scale: Double(request.scale))
        let snapY = DevicePixelSnap.edges(origin: Double(request.bounds.y), length: Double(request.bounds.h), scale: Double(request.scale))
        let boundsX = Float(snapX.origin), boundsY = Float(snapY.origin)
        let boundsW = Float(snapX.length), boundsH = Float(snapY.length)
        guard boundsW > 0, boundsH > 0 else { throw HostPaintError.continuousShapeRasterInput(2) }
        // `.stroke` centres its line on the path, so half the line width extends outside the snapped bounds. Apple
        // anti-aliases at the true fractional position, while GPUI floors an image origin to whole pixels. So the bitmap
        // is placed at the integer origin at or before the stroked outer edge and the fractional remainder is baked in.
        let halfStroke = request.strokeWidthPX / 2
        let outerX = boundsX - halfStroke, outerY = boundsY - halfStroke
        let originX = outerX.rounded(.down), originY = outerY.rounded(.down)
        let fracX = Double(outerX) - Double(originX), fracY = Double(outerY) - Double(originY)
        let width = max(1, Int((fracX + Double(boundsW) + Double(request.strokeWidthPX)).rounded(.up)))
        let height = max(1, Int((fracY + Double(boundsH) + Double(request.strokeWidthPX)).rounded(.up)))
        return Layout(originX: originX, originY: originY, fracX: fracX, fracY: fracY, boundsW: boundsW, boundsH: boundsH, width: width, height: height)
    }

    public static func render(_ request: ContinuousShapeRequest, band: (top: Int, rows: Int)?) throws -> Result {
        let l = try layout(request)
        let width = l.width, height = l.height
        if let band, band.rows * width > ContinuousRoundedRasterizer.workPixelLimit { throw HostPaintError.continuousShapeRasterInput(4) }
        let image = try ContinuousRoundedRasterizer.rasterize(
            width: width, height: band?.rows ?? height,
            cornerRadius: CGFloat(request.cornerRadiusPX),
            fillRGBA: request.fillRGBA,
            strokeRGBA: request.strokeRGBA,
            strokeWidth: CGFloat(request.strokeWidthPX),
            shapeWidth: CGFloat(l.boundsW), shapeHeight: CGFloat(l.boundsH),
            offsetX: CGFloat(l.fracX), offsetY: CGFloat(l.fracY), bandTop: band?.top ?? 0)
        let rows = band?.rows ?? height
        let placement = Rect(x: l.originX + imageGuardBand, y: l.originY + Float(band?.top ?? 0) + imageGuardBand,
                             w: Float(width) - 2 * imageGuardBand, h: Float(rows) - 2 * imageGuardBand)
        return Result(image: image, placement: placement)
    }


    /// The raster of one continuous shape as horizontal bands, each within the rasteriser's work limit (a card at 2.5x is 3.4 Mpx; round 5 block 30). One band for
    /// a shape within the limit, identical to `render`. A band is a window onto the same path, so the bands abut exactly (no seam, no overlap).
    public static func renderBands(_ request: ContinuousShapeRequest, maxTotalPixels: Int = 64_000_000) throws -> [Result] {
        let l = try layout(request)
        let width = l.width, height = l.height
        guard width * height > ContinuousRoundedRasterizer.workPixelLimit else { return [try render(request, band: nil)] }
        guard width <= ContinuousRoundedRasterizer.workPixelLimit, width * height <= maxTotalPixels else { throw HostPaintError.continuousShapeRasterInput(3) }
        let rows = max(1, ContinuousRoundedRasterizer.workPixelLimit / width)
        var out: [Result] = []
        var top = 0
        while top < height {
            let h = min(rows, height - top)
            out.append(try render(request, band: (top, h)))
            top += h
        }
        return out
    }

    public static func render(_ request: ContinuousShapeRequest) throws -> Result { try render(request, band: nil) }

    /// Rasterises and registers: the returned handle is owned by the caller until the node is removed.
    public static func primitive(_ registry: ImageRegistering, _ request: ContinuousShapeRequest) throws -> (primitive: Primitive, image: ImageHandle) {
        let result = try render(request)
        let handle = try registry.registerImage(width: UInt32(result.image.width), height: UInt32(result.image.height),
                                                rgba: result.image.rgba, stride: 0)
        return (.image(handle, result.placement), handle)
    }
}
