import Foundation
import SwiftRightRuntime

/// Declared substitute provider entry. Name resolution is data driven; provider
/// identity is observable & never implies SF Symbol parity.
struct FactorySystemImageGlyphDescriptor: Sendable {
    let name: String
    let providerFamily: String
    let providerVersion: String
    let glyph: UInt32
    let foregroundSemantic: String
    let parity: String
}

struct FactorySystemImageRaster: Sendable {
    let rgba: [UInt8]
    let width: UInt32
    let height: UInt32
    let glyphWidth: UInt32
    let glyphHeight: UInt32
    let renderedWidth: UInt32
    let renderedHeight: UInt32
    let nonZeroCoverage: UInt32
    let maxCoverage: UInt8
    let averageCharWidth: Int32
    let cellIncrementX: Int32
    let cellIncrementY: Int32
    let fontHeight: Int32
    let fontAscent: Int32
    let glyphOriginX: Int32
    let glyphOriginY: Int32
    let selectedFace: String
    // Mac-metric placement report (placement = "none" without layout metrics)
    var placement = "none"
    var halfCoverageBox = "n/a"
    var macInkBox = "n/a"
    var deviceInkMatched = "n/a"
    var inkRect = "n/a"
}

enum FactorySystemImageProviderError: Error {
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
}

/// Thin Windows host adapter: native glyph selection & coverage live in
/// SwiftRightRuntime; ABI 0.6 registration remains factory-owned.
enum FactorySystemImageProvider {
    private static func mapNativeError(_ error: Error) -> FactorySystemImageProviderError {
        guard let native = error as? WindowsSystemImageProviderError else {
            return .glyphBufferInvalid
        }
        switch native {
        case .invalidRequest: return .invalidTarget
        case .deviceContextUnavailable: return .deviceContextUnavailable
        case .fontUnavailable: return .fontUnavailable
        case .selectedFaceMismatch: return .fontSelectionFailed
        case .metricsUnavailable: return .metricsUnavailable
        case .glyphUnavailable: return .glyphUnavailable
        case .coverageUnavailable: return .glyphBufferInvalid
        }
    }

    static func rasterize(_ descriptor: FactorySystemImageGlyphDescriptor,
                          width: UInt32, height: UInt32, tint: UInt32,
                          layout: SystemImageLayoutMetrics? = nil, deviceInk: SystemImageDeviceInkBox? = nil, inset: UInt32 = 0, oversample: UInt32 = 1) throws -> FactorySystemImageRaster {
        guard !descriptor.name.isEmpty, descriptor.name.utf8.count <= 128,
              !descriptor.providerFamily.isEmpty, descriptor.providerFamily.utf8.count <= 128,
              !descriptor.providerVersion.isEmpty, descriptor.parity == "substitute-provider-unverified",
              descriptor.glyph <= 0x10ffff else { throw FactorySystemImageProviderError.invalidDescriptor }
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              UInt64(width) * UInt64(height) * 4 <= 16 * 1024 * 1024 else {
            throw FactorySystemImageProviderError.invalidTarget
        }

        // With Mac layout metrics the glyph is rasterized oversampled and area-resampled onto the symbol's ink rect.
        let canvasW = width + 2 * inset, canvasH = height + 2 * inset
        let factor = layout == nil ? 1 : max(1, min(oversample, 4096 / max(canvasW, canvasH)))
        let request = WindowsSystemImageGlyphRequest(providerFamily: descriptor.providerFamily,
                                                      glyph: descriptor.glyph,
                                                      targetWidth: canvasW * factor,
                                                      targetHeight: canvasH * factor)
        let native: WindowsSystemImageGlyphCoverage
        do {
            native = try WindowsSystemImageProvider.rasterize(request)
        } catch {
            throw mapNativeError(error)
        }
        let input = SystemImageRasterInput(sourceWidth: native.sourceWidth,
                                           sourceHeight: native.sourceHeight,
                                           rowBytes: native.rowBytes,
                                           coverage: native.coverage,
                                           coverageMaximum: native.coverageMaximum,
                                           rowOrder: native.rowOrder,
                                           selectedFace: native.selectedFace,
                                           expectedFace: descriptor.providerFamily)
        let composed: SystemImageRasterOutput
        var report: (String, String, String, String, String) = ("none", "n/a", "n/a", "n/a", "n/a")
        do {
            if let layout {
                let aligned = try SystemImageRasterProvider.composeAligned(input, metrics: layout, deviceInk: deviceInk,
                                                                           targetWidth: width, targetHeight: height, inset: inset, tintRGBA: tint)
                composed = aligned.raster
                let b = aligned.halfCoverageBox
                report = (deviceInk == nil ? "linear-mac-metrics" : "mac-device-ink-box",
                          "\(b.left),\(b.top),\(b.right),\(b.bottom)",
                          deviceInk.map { "\($0.left),\($0.top),\($0.right),\($0.bottom)" } ?? "n/a",
                          aligned.deviceInkMatched.map(String.init) ?? "n/a",
                          String(format: "%.3f,%.3f,%.3f,%.3f", aligned.inkRect.x, aligned.inkRect.y,
                                 aligned.inkRect.width, aligned.inkRect.height))
            } else {
                composed = try SystemImageRasterProvider.compose(input, targetWidth: width,
                                                                  targetHeight: height,
                                                                  tintRGBA: tint, aspectFit: true)
            }
        } catch SystemImageRasterError.emptyCoverage {
            throw FactorySystemImageProviderError.emptyCoverage
        } catch SystemImageRasterError.selectedFaceMismatch {
            throw FactorySystemImageProviderError.fontSelectionFailed
        } catch {
            throw FactorySystemImageProviderError.rasterCompositionFailed
        }
        var result = FactorySystemImageRaster(rgba: composed.rgba, width: composed.width,
            height: composed.height, glyphWidth: native.sourceWidth, glyphHeight: native.sourceHeight,
            renderedWidth: composed.renderedWidth, renderedHeight: composed.renderedHeight,
            nonZeroCoverage: composed.nonZeroCoverage, maxCoverage: composed.maxCoverage,
            averageCharWidth: native.averageCharWidth,
            cellIncrementX: native.cellIncrementX, cellIncrementY: native.cellIncrementY,
            fontHeight: native.fontHeight, fontAscent: native.fontAscent,
            glyphOriginX: native.glyphOriginX, glyphOriginY: native.glyphOriginY,
            selectedFace: native.selectedFace)
        (result.placement, result.halfCoverageBox, result.macInkBox, result.deviceInkMatched, result.inkRect) = report
        return result
    }
}
