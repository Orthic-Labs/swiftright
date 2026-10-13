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
                          width: UInt32, height: UInt32, tint: UInt32) throws -> FactorySystemImageRaster {
        guard !descriptor.name.isEmpty, descriptor.name.utf8.count <= 128,
              !descriptor.providerFamily.isEmpty, descriptor.providerFamily.utf8.count <= 128,
              !descriptor.providerVersion.isEmpty, descriptor.parity == "substitute-provider-unverified",
              descriptor.glyph <= 0x10ffff else { throw FactorySystemImageProviderError.invalidDescriptor }
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              UInt64(width) * UInt64(height) * 4 <= 16 * 1024 * 1024 else {
            throw FactorySystemImageProviderError.invalidTarget
        }

        let request = WindowsSystemImageGlyphRequest(providerFamily: descriptor.providerFamily,
                                                      glyph: descriptor.glyph,
                                                      targetWidth: width,
                                                      targetHeight: height)
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
        do {
            composed = try SystemImageRasterProvider.compose(input, targetWidth: width,
                                                              targetHeight: height,
                                                              tintRGBA: tint, aspectFit: true)
        } catch SystemImageRasterError.emptyCoverage {
            throw FactorySystemImageProviderError.emptyCoverage
        } catch SystemImageRasterError.selectedFaceMismatch {
            throw FactorySystemImageProviderError.fontSelectionFailed
        } catch {
            throw FactorySystemImageProviderError.rasterCompositionFailed
        }
        return FactorySystemImageRaster(rgba: composed.rgba, width: composed.width,
            height: composed.height, glyphWidth: native.sourceWidth, glyphHeight: native.sourceHeight,
            renderedWidth: composed.renderedWidth, renderedHeight: composed.renderedHeight,
            nonZeroCoverage: composed.nonZeroCoverage, maxCoverage: composed.maxCoverage,
            averageCharWidth: native.averageCharWidth,
            cellIncrementX: native.cellIncrementX, cellIncrementY: native.cellIncrementY,
            fontHeight: native.fontHeight, fontAscent: native.fontAscent,
            glyphOriginX: native.glyphOriginX, glyphOriginY: native.glyphOriginY,
            selectedFace: native.selectedFace)
    }
}
