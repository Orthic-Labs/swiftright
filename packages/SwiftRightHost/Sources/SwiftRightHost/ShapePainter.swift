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
/// A vector path to rasterise on the host: the shape's geometry resolved against the snapped pixel bounds, with its paint and styles.
/// `strokeStyle.lineWidth` is in points (scaled by `scale` in the rasteriser, like the path itself).
public struct PathShapeRequest: Equatable {
    /// A rotation (or a composition of them) in window pixels, applied after the shape is placed at its snapped origin (`.rotationEffect`, #35). Identity when the shape is not rotated.
    public var rotation: CGAffineTransform = .identity
    public var bounds: Rect
    public var scale: Float
    public var geometry: ShapeGeometry
    public var fillRGBA: UInt32?
    public var strokeRGBA: UInt32?
    public var strokeStyle: StrokeStyle
    public var fillStyle: FillStyle
    public init(bounds: Rect, scale: Float, geometry: ShapeGeometry, fillRGBA: UInt32?, strokeRGBA: UInt32?,
                strokeStyle: StrokeStyle = StrokeStyle(), fillStyle: FillStyle = FillStyle()) {
        self.bounds = bounds; self.scale = scale; self.geometry = geometry; self.fillRGBA = fillRGBA
        self.strokeRGBA = strokeRGBA; self.strokeStyle = strokeStyle; self.fillStyle = fillStyle
    }
}

/// One `.rotationEffect(_:anchor:)` above a shape, resolved to window pixels: the angle in radians (positive turns clockwise on screen, y down, as SwiftUI) and the anchor point
/// (the unit anchor placed in the modifier node's pixel frame). The renderer ABI transform is translation only, so a shape's rotation is folded into its path raster.
public struct ShapeRotation: Equatable {
    public var radians: Double
    public var anchorX: Double
    public var anchorY: Double
    public init(radians: Double, anchorX: Double, anchorY: Double) { self.radians = radians; self.anchorX = anchorX; self.anchorY = anchorY }
    public init(_ resolved: ResolvedRotation, bounds: Rect) {
        self.init(radians: resolved.angle.radians, anchorX: Double(bounds.x) + Double(resolved.anchor.x) * Double(bounds.w),
                  anchorY: Double(bounds.y) + Double(resolved.anchor.y) * Double(bounds.h))
    }
    /// True when the rotation moves nothing (a whole number of turns).
    public var isIdentity: Bool { !radians.isFinite ? false : radians.truncatingRemainder(dividingBy: 2 * Double.pi) == 0 }
    /// x' = cos (x - ax) - sin (y - ay) + ax, y' = sin (x - ax) + cos (y - ay) + ay (the y-down screen rotation about the anchor).
    public var transform: CGAffineTransform {
        let c = cos(radians), s = sin(radians)
        return CGAffineTransform(a: CGFloat(c), b: CGFloat(s), c: CGFloat(-s), d: CGFloat(c),
                                 tx: CGFloat(anchorX - c * anchorX + s * anchorY), ty: CGFloat(anchorY - s * anchorX - c * anchorY))
    }
    /// The combined transform of nested rotations, listed outermost first: the innermost applies first, then each one outside it.
    public static func combined(_ rotations: [ShapeRotation]) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        for r in rotations.reversed() where !r.isIdentity { t = concatenate(t, r.transform) }
        return t
    }
    /// `first` then `second` (the same product as `CGAffineTransform.concatenating`, written out so no platform shim is relied on).
    static func concatenate(_ first: CGAffineTransform, _ second: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: first.a * second.a + first.b * second.c, b: first.a * second.b + first.b * second.d,
                          c: first.c * second.a + first.d * second.c, d: first.c * second.b + first.d * second.d,
                          tx: first.tx * second.a + first.ty * second.c + second.tx, ty: first.tx * second.b + first.ty * second.d + second.ty)
    }
    public static func isRotated(_ rotations: [ShapeRotation]) -> Bool { rotations.contains { !$0.isIdentity } }
}

public enum ShapePaintPlan {
    case primitive(Primitive)
    case continuous(ContinuousShapeRequest)
    /// A trimmed, inset, dashed, custom or path shape, or a stroke style the ABI rect cannot draw: rasterised by `PathRasterizer`.
    case path(PathShapeRequest)
}

public enum ShapePainter {
    /// Resolves a Rectangle / RoundedRectangle / Circle node to its paint, from runtime geometry and paint only.
    /// `rotations` are the `.rotationEffect`s above the node (outermost first, anchors in the same window pixels as `bounds`): a rotated shape always takes the path route, with the rotation in its request.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float, rotations: [ShapeRotation] = []) throws -> ShapePaintPlan {
        guard let shape = node.shape else { throw HostPaintError.shapeMetadataRequired }
        let paint = shape.paint ?? ShapePaint.implicitFill(foreground: node.style.foreground)
        let colour = try HostPaint.rgba(paint.color, opacity: node.opacity, scheme: node.style.colorScheme)
        var strokeWidth: Float = 0
        if paint.kind == .stroke {
            guard let logical = paint.lineWidth, logical.isFinite, logical >= 0 else { throw HostPaintError.shapeStrokeWidthRequired }
            strokeWidth = Float(logical) * scale
            guard strokeWidth.isFinite else { throw HostPaintError.invalidScaledStrokeWidth }
        }
        let rotated = ShapeRotation.isRotated(rotations)
        if rotated || needsPathRoute(shape.geometry, paint) {
            let stroke = paint.kind == .stroke
            var request = PathShapeRequest(bounds: bounds, scale: scale, geometry: shape.geometry,
                                          fillRGBA: stroke ? nil : colour, strokeRGBA: stroke ? colour : nil,
                                          strokeStyle: paint.strokeStyle ?? StrokeStyle(lineWidth: paint.lineWidth ?? 0),
                                          fillStyle: paint.fillStyle ?? FillStyle())
            if rotated { request.rotation = ShapeRotation.combined(rotations) }
            return .path(request)
        }
        var frame = bounds
        var radius: Float = 0
        switch shape.geometry {
        case .capsule(let style):
            // A pill: the corner radius is half the short side (a circular pill is a plain ABI rect).
            switch style {
            case .circular:
                radius = min(bounds.w, bounds.h) / 2
            case .continuous:
                return .continuous(ContinuousShapeRequest(
                    bounds: bounds, cornerRadiusPX: min(bounds.w, bounds.h) / 2,
                    fillRGBA: paint.kind == .fill ? colour : nil,
                    strokeRGBA: paint.kind == .stroke ? colour : nil,
                    strokeWidthPX: strokeWidth, scale: scale))
            }
        case .path, .trimmed, .inset, .custom:
            preconditionFailure("path geometries take the path route above")
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

    /// True when a shape cannot go through the ABI rect or the continuous-corner raster: a path, custom, trimmed or inset geometry, a dashed stroke,
    /// or a rectangle stroke whose join is not the default miter (a plain rectangle's 90 degree corner needs a miter ratio of 1.414).
    /// Plain Circle, Rectangle, RoundedRectangle and Capsule fills and strokes stay on today's route (caps and joins are invisible on a closed smooth outline).
    static func needsPathRoute(_ geometry: ShapeGeometry, _ paint: ShapePaint) -> Bool {
        switch geometry {
        case .path, .custom, .trimmed, .inset: return true
        case .rectangle, .roundedRectangle, .circle, .capsule: break
        }
        guard paint.kind == .stroke, let style = paint.strokeStyle else { return false }
        if style.dash.contains(where: { $0 > 0 }), !style.dash.contains(where: { $0 < 0 || !$0.isFinite }) { return true }
        if case .rectangle = geometry, style.lineJoin != .miter || style.miterLimit < 2.0.squareRoot() { return true }
        return false
    }
}

/// Rasterises a `PathShapeRequest`: resolves the geometry against the same device-pixel-snapped bounds as the continuous route (SwiftUI draws a frame on whole
/// device pixels), builds the path in points, and rasterises it in pixels with the snapped origin as the transform. The bitmap sits on an integer origin, so no
/// fractional offset has to be baked in (the path itself carries it).
public enum PathShapeRaster {
    public struct Result: Equatable {
        public var image: ContinuousRGBAImage
        public var placement: Rect
    }

    /// Nil when there is nothing to draw (an empty path, a zero-length trim, no area).
    public static func render(_ request: PathShapeRequest) throws -> Result? {
        guard request.bounds.w.isFinite, request.bounds.h.isFinite, request.bounds.x.isFinite, request.bounds.y.isFinite,
              request.scale.isFinite, request.scale > 0 else { throw HostPaintError.pathShapeRasterInput(1) }
        let strokeWidthPoints = Double(request.strokeStyle.lineWidth)
        guard request.strokeRGBA == nil || (strokeWidthPoints.isFinite && strokeWidthPoints >= 0) else { throw HostPaintError.pathShapeRasterInput(2) }
        let snapX = DevicePixelSnap.edges(origin: Double(request.bounds.x), length: Double(request.bounds.w), scale: Double(request.scale))
        let snapY = DevicePixelSnap.edges(origin: Double(request.bounds.y), length: Double(request.bounds.h), scale: Double(request.scale))
        guard snapX.length > 0, snapY.length > 0 else { return nil }
        let scale = Double(request.scale)
        let rect = CGRect(x: 0, y: 0, width: snapX.length / scale, height: snapY.length / scale)
        let path = request.geometry.makePath(in: rect)
        // Placed at the snapped origin, then rotated in window pixels (identity unless under `.rotationEffect`). The raster's bounds come from the transformed outline, so a rotated shape is never clipped.
        let placed = ShapeRotation.concatenate(CGAffineTransform(translationX: CGFloat(snapX.origin), y: CGFloat(snapY.origin)), request.rotation)
        guard let raster = try PathRasterizer.rasterize(
            path: path, transform: placed, scale: CGFloat(scale),
            fillRGBA: request.fillRGBA, fillStyle: request.fillStyle,
            strokeRGBA: request.strokeRGBA, strokeStyle: request.strokeStyle) else { return nil }
        let placement = Rect(x: Float(raster.originX) + imageGuardBand, y: Float(raster.originY) + imageGuardBand,
                             w: Float(raster.image.width) - 2 * imageGuardBand, h: Float(raster.image.height) - 2 * imageGuardBand)
        return Result(image: raster.image, placement: placement)
    }

    /// Rasterises and registers: the returned handle is owned by the caller until the node is removed. Nil when there is nothing to draw.
    public static func primitive(_ registry: ImageRegistering, _ request: PathShapeRequest) throws -> (primitive: Primitive, image: ImageHandle)? {
        guard let result = try render(request) else { return nil }
        let handle = try registry.registerImage(width: UInt32(result.image.width), height: UInt32(result.image.height), rgba: result.image.rgba, stride: 0)
        return (.image(handle, result.placement), handle)
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
