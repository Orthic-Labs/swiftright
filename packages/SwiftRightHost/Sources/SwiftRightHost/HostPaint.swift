import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Failures of the product paint path. Every one is visible to the host; nothing falls back silently.
public enum HostPaintError: Error, Equatable, CustomStringConvertible {
    case invalidFillOpacity
    case invalidRGBAFill
    case unsupportedSemanticFill(String)
    case colorMetadataRequired
    case shapeMetadataRequired
    case shapeStrokeWidthRequired
    case invalidScaledStrokeWidth
    case unsupportedTextPaintStyle
    case measuredRunGeometryMismatch(String)
    case ambiguousMeasuredRun(String)
    case unsupportedNode(String)
    case systemImageContractMismatch(String)
    case continuousShapeRasterInput(Int)

    public var description: String {
        switch self {
        case .invalidFillOpacity: return "HostPaint: fill opacity outside 0...1"
        case .invalidRGBAFill: return "HostPaint: RGBA fill component outside 0...1"
        case .unsupportedSemanticFill(let name): return "HostPaint: unsupported semantic fill '\(name)'"
        case .colorMetadataRequired: return "HostPaint: Color node without resolved colour metadata"
        case .shapeMetadataRequired: return "HostPaint: shape node without resolved geometry/paint"
        case .shapeStrokeWidthRequired: return "HostPaint: stroke without a finite non-negative line width"
        case .invalidScaledStrokeWidth: return "HostPaint: scaled stroke width is not finite"
        case .unsupportedTextPaintStyle: return "HostPaint: Text with a foreground style or opacity is not painted yet"
        case .measuredRunGeometryMismatch(let text): return "HostPaint: no measured run matches the resolved bounds of '\(text)'"
        case .ambiguousMeasuredRun(let text): return "HostPaint: several different measured runs match '\(text)'"
        case .unsupportedNode(let kind): return "HostPaint: unsupported node kind '\(kind)'"
        case .systemImageContractMismatch(let why): return "HostPaint: Image(systemName:) contract mismatch (\(why))"
        case .continuousShapeRasterInput(let code): return "HostPaint: continuous shape raster input invalid (\(code))"
        }
    }
}

/// Windows paint policy for resolved colours: native RGBA bytes (0xRRGGBBAA) for the semantic colours the runtime
/// resolves (observed system colours), and explicit RGBA scaled by the node opacity.
public enum HostPaint {
    public static func rgba(_ value: ResolvedColor, opacity: Double) throws -> UInt32 {
        switch value {
        case .rgba(let r, let g, let b, let a):
            return try rgba(components: [r, g, b, a], opacity: opacity)
        case .semantic(let name):
            guard opacity.isFinite, opacity >= 0, opacity <= 1 else { throw HostPaintError.invalidFillOpacity }
            let raw = try semantic(name)
            return (raw & 0xffffff00) | UInt32((Double(raw & 255) * opacity).rounded())
        }
    }

    public static func rgba(components values: [Double], opacity: Double) throws -> UInt32 {
        guard values.count == 4, values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
            throw HostPaintError.invalidRGBAFill
        }
        guard opacity.isFinite, opacity >= 0, opacity <= 1 else { throw HostPaintError.invalidFillOpacity }
        let bytes = values.prefix(3).map { UInt32(($0 * 255).rounded()) }
        let alpha = UInt32((values[3] * opacity * 255).rounded())
        return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | alpha
    }

    public static func semantic(_ name: String) throws -> UInt32 {
        let native: [String: UInt32] = [
            "system.red": 0xff383cff,
            "system.blue": 0x0088ffff,
            "system.yellow": 0xffcc00ff,
            // macOS light-appearance system colours, read from SwiftUI renders at scale 2.5 (the capture scale).
            "system.orange": 0xff8d28ff,
            "system.green": 0x34c759ff,
            "system.purple": 0xcb30e0ff,
            "system.pink": 0xff2d55ff,
            "system.gray": 0x8e8e93ff,
            "black": 0x000000ff,
            "white": 0xffffffff,
            "clear": 0x00000000,
        ]
        guard let value = native[name] else { throw HostPaintError.unsupportedSemanticFill(name) }
        return value
    }
}

/// The image-handle surface the paint path needs from the renderer bridge (a protocol so the pure paint
/// logic is testable without a renderer).
public protocol ImageRegistering: AnyObject {
    func registerImage(width: UInt32, height: UInt32, rgba: [UInt8], stride: UInt32) throws -> ImageHandle
    @discardableResult func release(_ image: ImageHandle) -> Bool
}

extension Bridge: ImageRegistering {}

/// GPUI floors an image origin and ceils its size after scaling logical bounds by the display scale in f32, so an
/// integral device-pixel rect can land a whole pixel off. Images are nudged strictly inside their pixel cell.
let imageGuardBand: Float = 1.0 / 64

/// Whether a snapped (device pixel) extent can be what the runtime derived from a measured physical extent.
/// Runtime size divides physical Float32 by Float32 scale before CGFloat conversion, then edge snapping multiplies in
/// CGFloat (Double on Windows). Unknown fractional origin permits floor(d)/ceil(d); integer d also permits d+1 when
/// nearest-away half ties cross zero.
func snappedExtentCanMatch(_ measured: Float, _ snapped: Float, origin: Float = 0, scale: Float = 1) -> Bool {
    guard measured.isFinite, snapped.isFinite, origin.isFinite, scale.isFinite,
          scale > 0, measured >= 0, snapped >= 0, snapped == snapped.rounded(),
          origin == origin.rounded() else { return false }
    let extent = Double(measured / scale) * Double(scale)
    guard extent.isFinite else { return false }
    let output = Double(snapped)
    if output == extent.rounded(.down) || output == extent.rounded(.up) { return true }
    return extent >= 1 && extent == extent.rounded() && output == extent + 1 &&
      origin < 0 && origin + snapped > 0
}
