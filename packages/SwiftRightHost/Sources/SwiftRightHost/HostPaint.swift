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
    case pathShapeRasterInput(Int)
    case unsupportedToggleStyle(String)
    case unsupportedTogglePaintStyle
    case unsupportedButtonPaintStyle
    case unsupportedListStyle(String)
    case sliderMetadataRequired
    case unsupportedSliderPaintStyle

    public var description: String {
        switch self {
        case .invalidFillOpacity: return "HostPaint: fill opacity outside 0...1"
        case .invalidRGBAFill: return "HostPaint: RGBA fill component outside 0...1"
        case .unsupportedSemanticFill(let name): return "HostPaint: unsupported semantic fill '\(name)'"
        case .colorMetadataRequired: return "HostPaint: Color node without resolved colour metadata"
        case .shapeMetadataRequired: return "HostPaint: shape node without resolved geometry/paint"
        case .shapeStrokeWidthRequired: return "HostPaint: stroke without a finite non-negative line width"
        case .invalidScaledStrokeWidth: return "HostPaint: scaled stroke width is not finite"
        case .unsupportedTextPaintStyle: return "HostPaint: Text with opacity is not painted yet"
        case .measuredRunGeometryMismatch(let text): return "HostPaint: no measured run matches the resolved bounds of '\(text)'"
        case .ambiguousMeasuredRun(let text): return "HostPaint: several different measured runs match '\(text)'"
        case .unsupportedNode(let kind): return "HostPaint: unsupported node kind '\(kind)'"
        case .systemImageContractMismatch(let why): return "HostPaint: Image(systemName:) contract mismatch (\(why))"
        case .continuousShapeRasterInput(let code): return "HostPaint: continuous shape raster input invalid (\(code))"
        case .pathShapeRasterInput(let code): return "HostPaint: path shape raster input invalid (\(code))"
        case .unsupportedToggleStyle(let style): return "HostPaint: Toggle style '\(style)' has no artwork yet (only the switch and checkbox styles are painted)"
        case .unsupportedTogglePaintStyle: return "HostPaint: Toggle with a foreground style or opacity is not painted yet"
        case .unsupportedListStyle(let style): return "HostPaint: List style '\(style)' has no artwork yet (only the automatic, inset and plain styles are painted)"
        case .sliderMetadataRequired: return "HostPaint: Slider node without resolved value, bounds or an empty control"
        case .unsupportedSliderPaintStyle: return "HostPaint: Slider with a foreground style or opacity is not painted yet"
        case .unsupportedButtonPaintStyle: return "HostPaint: Button with a foreground style, opacity or an empty frame is not painted yet"
        }
    }
}

/// Windows paint policy for resolved colours: native RGBA bytes (0xRRGGBBAA) for the semantic colours the runtime
/// resolves (observed system colours), and explicit RGBA scaled by the node opacity.
public enum HostPaint {
    public static func rgba(_ value: ResolvedColor, opacity: Double, scheme: ColorScheme = .light) throws -> UInt32 {
        switch value {
        case .rgba(let r, let g, let b, let a):
            return try rgba(components: [r, g, b, a], opacity: opacity)
        case .semanticAlpha(let name, let alpha):
            guard alpha.isFinite, alpha >= 0, alpha <= 1 else { throw HostPaintError.invalidFillOpacity }
            return try rgba(.semantic(name), opacity: opacity * alpha, scheme: scheme)
        case .semantic(let name):
            guard opacity.isFinite, opacity >= 0, opacity <= 1 else { throw HostPaintError.invalidFillOpacity }
            let raw = try semantic(name, scheme: scheme)
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

    /// Semantic colour names the runtime resolves, as 0xRRGGBBAA in `scheme`. Light: macOS light-appearance system colours; dark: the same names measured with the
    /// dark appearance (`.environment(\.colorScheme, .dark)` in an NSHostingView whose window appearance is darkAqua), SwiftUI renders at scale 2.5 (block 20).
    /// `label` / `secondaryLabel` (Color.primary / .secondary) are translucent (alpha 216 and 127 light, 216 and 140 dark); `background` is the window background.
    public static func semantic(_ name: String, scheme: ColorScheme = .light) throws -> UInt32 {
        if scheme == .dark, let value = darkSemantic[name] { return value }
        return try semanticLight(name)
    }

    static let darkSemantic: [String: UInt32] = [
        "system.red": 0xff4245ff,
        "system.blue": 0x0091ffff,
        "system.yellow": 0xffd600ff,
        "system.orange": 0xff9230ff,
        "system.green": 0x30d158ff,
        "system.purple": 0xdb34f2ff,
        "system.pink": 0xff375fff,
        "system.gray": 0x98989dff,
        "label": 0xffffffd8,
        "secondaryLabel": 0xffffff8c,
        "accentColor": 0x007affff,
        "background": 0x1e1e1eff,
        "separator": 0xffffff19,   // Divider, dark appearance (round 5 block 31): white at alpha 25/255 (52 over the dark window ground (30), (25,156,255) over (0,145,255))
        "clear": 0x00000000,
    ]

    static func semanticLight(_ name: String) throws -> UInt32 {
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
            "label": 0x000000d8,
            "secondaryLabel": 0x0000007f,
            "accentColor": 0x007affff,
            "background": 0xffffffff,
            "separator": 0x00000019,   // Divider (block swiftui.spacer-divider): black at 25/255, light appearance only
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
