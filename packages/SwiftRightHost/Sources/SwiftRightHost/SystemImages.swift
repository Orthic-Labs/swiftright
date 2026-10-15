import Foundation
import SwiftRightRuntime
import SwiftRightBridge

public enum SystemImageError: Error, Equatable, CustomStringConvertible {
    case invalidDescriptor
    case invalidTarget
    case deviceContextUnavailable
    case fontUnavailable
    case fontSelectionFailed
    case metricsUnavailable
    case glyphUnavailable
    case glyphBufferInvalid
    case emptyCoverage
    case rasterCompositionFailed
    case providerEntryMissing(String)
    case glyphEncodingInvalid(String)
    case targetSizeInvalid

    public var description: String {
        switch self {
        case .invalidDescriptor: return "SystemImage: invalidDescriptor"
        case .invalidTarget: return "SystemImage: invalidTarget"
        case .deviceContextUnavailable: return "SystemImage: deviceContextUnavailable"
        case .fontUnavailable: return "SystemImage: fontUnavailable"
        case .fontSelectionFailed: return "SystemImage: fontSelectionFailed"
        case .metricsUnavailable: return "SystemImage: metricsUnavailable"
        case .glyphUnavailable: return "SystemImage: glyphUnavailable"
        case .glyphBufferInvalid: return "SystemImage: glyphBufferInvalid"
        case .emptyCoverage: return "SystemImage: emptyCoverage"
        case .rasterCompositionFailed: return "SystemImage: rasterCompositionFailed"
        case .providerEntryMissing(let name): return "SystemImage: providerEntryMissing(\(name))"
        case .glyphEncodingInvalid(let glyph): return "SystemImage: glyphEncodingInvalid(\(glyph))"
        case .targetSizeInvalid: return "SystemImage: targetSizeInvalid"
        }
    }
}

/// Native grayscale coverage of one glyph plus the selected face and cell metrics.
public struct SystemGlyphCoverage: Sendable {
    public var sourceWidth: UInt32, sourceHeight: UInt32, rowBytes: UInt32
    public var coverage: [UInt8]
    public var coverageMaximum: UInt8
    public var rowOrder: SystemImageRasterRowOrder
    public var selectedFace: String
    public var averageCharWidth: Int32 = 0, cellIncrementX: Int32 = 0, cellIncrementY: Int32 = 0
    public var fontHeight: Int32 = 0, fontAscent: Int32 = 0, glyphOriginX: Int32 = 0, glyphOriginY: Int32 = 0

    public init(sourceWidth: UInt32, sourceHeight: UInt32, rowBytes: UInt32, coverage: [UInt8], coverageMaximum: UInt8,
                rowOrder: SystemImageRasterRowOrder, selectedFace: String) {
        self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight; self.rowBytes = rowBytes
        self.coverage = coverage; self.coverageMaximum = coverageMaximum; self.rowOrder = rowOrder; self.selectedFace = selectedFace
    }
}

/// Where glyph coverage comes from. Windows: live GDI glyph outlines (`WindowsGlyphRasterizer`).
public protocol SystemGlyphRasterizing {
    func rasterize(providerFamily: String, glyph: UInt32, targetWidth: UInt32, targetHeight: UInt32) throws -> SystemGlyphCoverage
}

#if os(Windows)
/// Live Windows provider (GDI glyph outline of the exact declared face; a silently substituted face is refused).
public struct WindowsGlyphRasterizer: SystemGlyphRasterizing {
    public init() {}
    public func rasterize(providerFamily: String, glyph: UInt32, targetWidth: UInt32, targetHeight: UInt32) throws -> SystemGlyphCoverage {
        let native: WindowsSystemImageGlyphCoverage
        do {
            native = try WindowsSystemImageProvider.rasterize(WindowsSystemImageGlyphRequest(
                providerFamily: providerFamily, glyph: glyph, targetWidth: targetWidth, targetHeight: targetHeight))
        } catch let error as WindowsSystemImageProviderError {
            switch error {
            case .invalidRequest: throw SystemImageError.invalidTarget
            case .deviceContextUnavailable: throw SystemImageError.deviceContextUnavailable
            case .fontUnavailable: throw SystemImageError.fontUnavailable
            case .selectedFaceMismatch: throw SystemImageError.fontSelectionFailed
            case .metricsUnavailable: throw SystemImageError.metricsUnavailable
            case .glyphUnavailable: throw SystemImageError.glyphUnavailable
            case .coverageUnavailable: throw SystemImageError.glyphBufferInvalid
            }
        }
        var out = SystemGlyphCoverage(sourceWidth: native.sourceWidth, sourceHeight: native.sourceHeight, rowBytes: native.rowBytes,
                                      coverage: native.coverage, coverageMaximum: native.coverageMaximum,
                                      rowOrder: native.rowOrder, selectedFace: native.selectedFace)
        out.averageCharWidth = native.averageCharWidth; out.cellIncrementX = native.cellIncrementX; out.cellIncrementY = native.cellIncrementY
        out.fontHeight = native.fontHeight; out.fontAscent = native.fontAscent
        out.glyphOriginX = native.glyphOriginX; out.glyphOriginY = native.glyphOriginY
        return out
    }
}
#endif

/// One rasterised symbol with the report of how it was placed.
public struct SystemImageRaster: Sendable {
    public var rgba: [UInt8]
    public var width: UInt32, height: UInt32
    public var glyphWidth: UInt32, glyphHeight: UInt32
    public var renderedWidth: UInt32, renderedHeight: UInt32
    public var nonZeroCoverage: UInt32
    public var maxCoverage: UInt8
    public var selectedFace: String
    public var placement = "none"
    public var halfCoverageBox = "n/a"
    public var macInkBox = "n/a"
    public var inkBoxSource = "n/a"
    public var deviceInkMatched = "n/a"
    public var inkRect = "n/a"
}

/// Resolves `Image(systemName:)` through the symbol table: layout (intrinsic size, aspect-fit), the substitute glyph raster and
/// the registered image handle. The host wires the runtime's two image-size hooks with `install(on:)`.
@MainActor
public final class SystemImageRegistry {
    /// Symbols overflow their frames by a pixel or two; the raster canvas keeps that ink.
    public static let overflowInset: UInt32 = 4

    public let table: SystemImageTable
    private let images: ImageRegistering
    private let rasterizer: SystemGlyphRasterizing
    private let log: (String) -> Void
    private struct HandleKey: Hashable {
        let reference: ImageReference
        let tint: UInt32
        let width: UInt32
        let height: UInt32
        /// Point size of a font-sized (non-resizable) symbol; nil for resizable use.
        let fontSize: Double?
    }
    private var handles: [HandleKey: ImageHandle] = [:]
    /// Screen scale of the window; selects the Mac device-pixel ink calibration. Set before the first layout.
    public var scale: Double = 1

    public init(images: ImageRegistering, rasterizer: SystemGlyphRasterizing, table: SystemImageTable? = nil,
                log: @escaping (String) -> Void = { print($0) }) throws {
        self.images = images
        self.rasterizer = rasterizer
        self.table = try table ?? SystemImageTable.standard()
        self.log = log
        let p = self.table.providerPolicy
        log("SYSTEM_IMAGE_PROVIDER_POLICY kind=\(p.kind) resolution=\(p.resolution) rasterization=\(p.rasterization) cache=\(p.cache) parity=\(p.parity) symbols=\(self.table.symbols.count)")
    }

    private func entry(for reference: ImageReference) throws -> (name: String, symbol: SystemImageTable.Symbol) {
        guard case .system(let name) = reference, name.utf8.count <= 128, let symbol = table.symbols[name] else {
            throw SystemImageError.providerEntryMissing(reference.name)
        }
        return (name, symbol)
    }

    public func supports(_ reference: ImageReference) -> Bool {
        guard case .system(let name) = reference else { return false }
        return table.symbols[name] != nil
    }

    /// Runtime hook `Graph.imageIntrinsicSize`.
    public func intrinsicSize(for reference: ImageReference) -> LayoutSize {
        guard let (_, symbol) = try? entry(for: reference) else { return .zero }
        if let layout = symbol.layout {   // SF Symbol intrinsic size measured on the Mac
            return LayoutSize(width: CGFloat(layout.intrinsicSize[0]), height: CGFloat(layout.intrinsicSize[1]))
        }
        return LayoutSize(width: CGFloat(symbol.width), height: CGFloat(symbol.height))
    }

    /// The default environment font size on macOS (body, 13 pt): what an `Image(systemName:)` with no font is drawn at.
    public static let bodyPointSize: Double = 13

    /// Point size a SwiftUI font draws a symbol at, for the fonts whose symbol layout was measured: no font (body), `Font.system(size:)`
    /// in the regular weight and the text styles that are regular-weight system sizes (measured equal to the system font of that size).
    /// Nil for anything else (a custom family, a design, another weight, headline, caption2): those are not measured.
    public static func fontPointSize(_ font: Font?) -> Double? {
        guard let font else { return bodyPointSize }
        guard let m = font.metadata else { return font.id == "textStyle.body" ? bodyPointSize : nil }
        guard !m.isCustom, m.familyName == nil, m.design == nil || m.design == .default, m.width == nil || m.width == .standard,
              m.weight == nil || m.weight == .regular else { return nil }
        if let size = m.pointSize, m.textStyle == nil, size.isFinite, size > 0 { return Double(size) }
        let styles: [String: Double] = ["largeTitle": 26, "title": 22, "title2": 17, "title3": 15, "body": 13, "callout": 12,
                                        "subheadline": 11, "footnote": 10, "caption": 10]
        return m.textStyle.flatMap { styles[$0] }
    }

    /// Whether this symbol was measured for font-sized (non-resizable) use.
    public func supportsFontSized(_ reference: ImageReference) -> Bool {
        (try? entry(for: reference))?.symbol.layout?.supportsFontSizes ?? false
    }
    /// Whether this symbol was measured for `resizable().scaledToFit()` use.
    public func supportsResizable(_ reference: ImageReference) -> Bool {
        (try? entry(for: reference))?.symbol.layout?.supportsResizable ?? false
    }

    /// Runtime hook `Graph.imageFontIntrinsicSize`: the Image view size of a non-resizable symbol drawn at the environment font.
    /// Nil for a symbol or font that was not measured (the runtime then keeps the natural size).
    public func fontIntrinsicSize(for reference: ImageReference, font: Font?) -> LayoutSize? {
        guard let (_, symbol) = try? entry(for: reference), let size = Self.fontPointSize(font),
              let l = symbol.layout?.fontLayout(pointSize: size, scale: scale), l.framePt.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return LayoutSize(width: CGFloat(l.framePt[0]), height: CGFloat(l.framePt[1]))
    }

    /// Runtime hook `Graph.imageFitIntrinsicSize`: what SwiftUI fits `resizable().scaledToFit()` symbols by.
    public func fitIntrinsicSize(for reference: ImageReference) -> LayoutSize? {
        guard let (_, symbol) = try? entry(for: reference), let size = symbol.layout?.fitIntrinsic(scale: scale),
              size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return LayoutSize(width: CGFloat(size[0]), height: CGFloat(size[1]))
    }

    /// Wires the two image hooks of a graph to this registry.
    public func install(on graph: Graph) {
        graph.imageIntrinsicSize = { [unowned self] reference in self.intrinsicSize(for: reference) }
        graph.imageFitIntrinsicSize = { [unowned self] reference in self.fitIntrinsicSize(for: reference) }
        graph.imageFontIntrinsicSize = { [unowned self] reference, font in self.fontIntrinsicSize(for: reference, font: font) }
    }

    /// The symbol's own foreground (semantic colour name) when the app sets none.
    public func defaultForeground(for reference: ImageReference) -> String {
        (try? entry(for: reference))?.symbol.foregroundSemantic ?? "black"
    }

    /// Canvas margin (px) around the frame for a symbol with layout metrics. A font-sized symbol at a large point size can overflow its frame by more
    /// than `overflowInset` (folder.badge.plus at 28 pt, scale 2.5: 5 px): the margin then grows to keep every ink pixel (bounded at 16).
    public func canvasInset(for reference: ImageReference, fontSize: Double? = nil, width: UInt32 = 0, height: UInt32 = 0) -> Float {
        guard let (_, symbol) = try? entry(for: reference), symbol.layout != nil else { return 0 }
        return Float(inset(symbol, fontSize: fontSize, width: width, height: height))
    }

    private func inset(_ symbol: SystemImageTable.Symbol, fontSize: Double?, width: UInt32, height: UInt32) -> UInt32 {
        guard let layout = symbol.layout else { return 0 }
        guard let fontSize, width > 0, height > 0, let box = layout.fontDeviceInkBox(pointSize: fontSize, scale: scale, widthPx: width, heightPx: height)?.box else {
            return Self.overflowInset
        }
        let over = max(0, -box.left, -box.top, box.right - Int(width), box.bottom - Int(height))
        return min(16, max(Self.overflowInset, UInt32(over + 1)))
    }

    /// Rasterises the symbol for a frame of `width` x `height` px (pure of the renderer; used by `handle` and by tests).
    /// `fontSize` selects the font-sized (non-resizable) layout model at that point size; nil is the resizable model.
    public func raster(for reference: ImageReference, tint: UInt32, width: UInt32, height: UInt32, fontSize: Double? = nil) throws -> SystemImageRaster {
        let (name, symbol) = try entry(for: reference)
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw SystemImageError.targetSizeInvalid }
        guard let glyph = UInt32(symbol.glyph.replacingOccurrences(of: "0x", with: ""), radix: 16), glyph <= 0x10ffff else {
            throw SystemImageError.glyphEncodingInvalid(symbol.glyph)
        }
        guard !name.isEmpty, !symbol.provider.isEmpty, symbol.provider.utf8.count <= 128, !symbol.providerVersion.isEmpty,
              table.providerPolicy.parity == "substitute-provider-unverified",
              UInt64(width) * UInt64(height) * 4 <= 16 * 1024 * 1024 else { throw SystemImageError.invalidDescriptor }
        let layout: SystemImageLayoutMetrics?
        if let fontSize {
            guard let l = symbol.layout, let m = l.fontMetrics(pointSize: fontSize, scale: scale) else { throw SystemImageError.invalidDescriptor }
            layout = m
        } else {
            layout = symbol.layout?.metrics(scale: scale)
        }
        let inset = symbol.layout == nil ? UInt32(0) : inset(symbol, fontSize: fontSize, width: width, height: height)
        let oversample = symbol.layout?.sourceOversample ?? 1
        // With Mac layout metrics the glyph is rasterised oversampled and area-resampled onto the symbol's ink rect.
        let canvasW = width + 2 * inset, canvasH = height + 2 * inset
        let factor = layout == nil ? 1 : max(1, min(oversample, 4096 / max(canvasW, canvasH)))
        let native = try rasterizer.rasterize(providerFamily: symbol.provider, glyph: glyph,
                                              targetWidth: canvasW * factor, targetHeight: canvasH * factor)
        let input = SystemImageRasterInput(sourceWidth: native.sourceWidth, sourceHeight: native.sourceHeight, rowBytes: native.rowBytes,
                                           coverage: native.coverage, coverageMaximum: native.coverageMaximum, rowOrder: native.rowOrder,
                                           selectedFace: native.selectedFace, expectedFace: symbol.provider)
        let composed: SystemImageRasterOutput
        var report = ("none", "n/a", "n/a", "n/a", "n/a", "n/a")
        do {
            if let layout {
                let device = fontSize != nil ? symbol.layout?.fontDeviceInkBox(pointSize: fontSize!, scale: scale, widthPx: width, heightPx: height)
                                            : symbol.layout?.deviceInkBox(scale: scale, widthPx: width, heightPx: height)
                let aligned = try SystemImageRasterProvider.composeAligned(input, metrics: layout, deviceInk: device?.box, targetWidth: width,
                                                                           targetHeight: height, inset: inset, tintRGBA: tint)
                composed = aligned.raster
                let b = aligned.halfCoverageBox
                report = (device == nil ? "linear-mac-metrics" : "mac-device-ink-box",
                          "\(b.left),\(b.top),\(b.right),\(b.bottom)",
                          device.map { "\($0.box.left),\($0.box.top),\($0.box.right),\($0.box.bottom)" } ?? "n/a",
                          device?.source ?? "n/a",
                          aligned.deviceInkMatched.map(String.init) ?? "n/a",
                          String(format: "%.3f,%.3f,%.3f,%.3f", aligned.inkRect.x, aligned.inkRect.y, aligned.inkRect.width, aligned.inkRect.height))
            } else {
                composed = try SystemImageRasterProvider.compose(input, targetWidth: width, targetHeight: height, tintRGBA: tint, aspectFit: true)
            }
        } catch SystemImageRasterError.emptyCoverage {
            throw SystemImageError.emptyCoverage
        } catch SystemImageRasterError.selectedFaceMismatch {
            throw SystemImageError.fontSelectionFailed
        } catch {
            throw SystemImageError.rasterCompositionFailed
        }
        var out = SystemImageRaster(rgba: composed.rgba, width: composed.width, height: composed.height,
                                    glyphWidth: native.sourceWidth, glyphHeight: native.sourceHeight,
                                    renderedWidth: composed.renderedWidth, renderedHeight: composed.renderedHeight,
                                    nonZeroCoverage: composed.nonZeroCoverage, maxCoverage: composed.maxCoverage,
                                    selectedFace: native.selectedFace)
        (out.placement, out.halfCoverageBox, out.macInkBox, out.inkBoxSource, out.deviceInkMatched, out.inkRect) = report
        return out
    }

    /// The registered image of a symbol for a frame size and tint (cached per reference, tint and size).
    public func handle(for reference: ImageReference, tint: UInt32, width: UInt32, height: UInt32, fontSize: Double? = nil) throws -> ImageHandle {
        let key = HandleKey(reference: reference, tint: tint, width: width, height: height, fontSize: fontSize)
        if let handle = handles[key] { return handle }
        let (name, symbol) = try entry(for: reference)
        let r = try raster(for: reference, tint: tint, width: width, height: height, fontSize: fontSize)
        let handle = try images.registerImage(width: r.width, height: r.height, rgba: r.rgba, stride: r.width * 4)
        handles[key] = handle
        log("SYSTEM_IMAGE name=\(name) provider=\(symbol.provider) providerVersion=\(symbol.providerVersion) glyph=\(symbol.glyph) targetBounds=\(r.width)x\(r.height) renderedBounds=\(r.renderedWidth)x\(r.renderedHeight) layoutMetrics=\(symbol.layout == nil ? "none" : "mac-measured") fontSize=\(fontSize.map { String($0) } ?? "resizable") placement=\(r.placement) halfCoverageBox=\(r.halfCoverageBox) macInkBox=\(r.macInkBox) inkBoxSource=\(r.inkBoxSource) deviceInkMatched=\(r.deviceInkMatched) inkRect=\(r.inkRect) tintRGBA=\(String(format: "%08x", tint)) nonZeroCoverage=\(r.nonZeroCoverage) maxCoverage=\(r.maxCoverage) selectedFace=\(r.selectedFace) parity=\(table.providerPolicy.parity)")
        return handle
    }

    public func releaseAll() {
        for handle in handles.values { _ = images.release(handle) }
        handles.removeAll(keepingCapacity: false)
    }
}
