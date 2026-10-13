import Foundation
import WinSDK

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
    let nonZeroCoverage: UInt32
    let maxCoverage: UInt8
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
}

/// Live GDI raster adapter for declared provider glyphs. ABI 0.6 only accepts
/// RGBA registration, so this returns target-sized coverage generated from current
/// provider font/glyph metrics; no cached sidecar bytes or Mac pixels are read.
enum FactorySystemImageProvider {
    private static func withWideCString<T>(_ value: String, _ body: (UnsafePointer<UInt16>) -> T) -> T {
        var units = Array(value.utf16) + [0]
        return units.withUnsafeBufferPointer { body($0.baseAddress!) }
    }

    static func rasterize(_ descriptor: FactorySystemImageGlyphDescriptor,
                          width: UInt32, height: UInt32, tint: UInt32) throws -> FactorySystemImageRaster {
        guard !descriptor.name.isEmpty, descriptor.name.utf8.count <= 128,
              !descriptor.providerFamily.isEmpty, descriptor.providerFamily.utf8.count <= 128,
              !descriptor.providerVersion.isEmpty, descriptor.parity == "substitute-provider-unverified",
              descriptor.glyph <= 0x10ffff else { throw FactorySystemImageProviderError.invalidDescriptor }
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              UInt64(width) * UInt64(height) <= (64 * 1024 * 1024) / 4 else {
            throw FactorySystemImageProviderError.invalidTarget
        }

        guard let dc = CreateCompatibleDC(nil) else { throw FactorySystemImageProviderError.deviceContextUnavailable }
        defer { _ = DeleteDC(dc) }
        let fontHeight = Int32(max(width, height))
        let font: HFONT? = withWideCString(descriptor.providerFamily) { family in
            CreateFontW(-fontHeight, 0, 0, 0, Int32(FW_NORMAL), 0, 0, 0,
                        UINT32(DEFAULT_CHARSET), UINT32(OUT_DEFAULT_PRECIS),
                        UINT32(CLIP_DEFAULT_PRECIS), UINT32(CLEARTYPE_QUALITY),
                        UINT32(DEFAULT_PITCH | FF_DONTCARE), family)
        }
        guard let font else { throw FactorySystemImageProviderError.fontUnavailable }
        defer { _ = DeleteObject(font) }
        guard let previous = SelectObject(dc, font) else { throw FactorySystemImageProviderError.fontSelectionFailed }
        defer { _ = SelectObject(dc, previous) }

        var faceBuffer = [UInt16](repeating: 0, count: 256)
        let faceLength = faceBuffer.withUnsafeMutableBufferPointer { buffer -> Int32 in
            GetTextFaceW(dc, Int32(buffer.count), buffer.baseAddress)
        }
        guard faceLength > 0, faceLength < Int32(faceBuffer.count) else {
            throw FactorySystemImageProviderError.fontSelectionFailed
        }
        let selectedFace = String(decoding: faceBuffer.prefix(Int(faceLength)), as: UTF16.self)
        guard !selectedFace.isEmpty else { throw FactorySystemImageProviderError.fontSelectionFailed }

        var textMetrics = TEXTMETRICW()
        guard GetTextMetricsW(dc, &textMetrics) else { throw FactorySystemImageProviderError.metricsUnavailable }
        let fixedOne = FIXED(fract: 0, value: 1)
        let fixedZero = FIXED(fract: 0, value: 0)
        var transform = MAT2(eM11: fixedOne, eM12: fixedZero, eM21: fixedZero, eM22: fixedOne)
        var glyphMetrics = GLYPHMETRICS()
        let glyphCode = descriptor.glyph
        let required = GetGlyphOutlineW(dc, glyphCode, UINT32(GGO_GRAY8_BITMAP), &glyphMetrics,
                                        0, nil, &transform)
        guard required != UInt32(GDI_ERROR), required > 0 else { throw FactorySystemImageProviderError.glyphUnavailable }
        let glyphWidth = UInt32(glyphMetrics.gmBlackBoxX), glyphHeight = UInt32(glyphMetrics.gmBlackBoxY)
        guard glyphWidth > 0, glyphHeight > 0, glyphWidth <= width * 4, glyphHeight <= height * 4,
              required <= 16 * 1024 * 1024 else { throw FactorySystemImageProviderError.glyphBufferInvalid }
        var bitmap = Array(repeating: UInt8(0), count: Int(required))
        let rendered = bitmap.withUnsafeMutableBytes { raw in
            GetGlyphOutlineW(dc, glyphCode, UINT32(GGO_GRAY8_BITMAP), &glyphMetrics,
                             required, raw.baseAddress, &transform)
        }
        guard rendered == required else { throw FactorySystemImageProviderError.glyphBufferInvalid }
        let rowBytes = (Int(glyphWidth) + 3) & ~3
        guard rowBytes * Int(glyphHeight) <= bitmap.count else { throw FactorySystemImageProviderError.glyphBufferInvalid }

        let targetWidth = Int(width), targetHeight = Int(height)
        var rgba = Array(repeating: UInt8(0), count: targetWidth * targetHeight * 4)
        let red = UInt8((tint >> 24) & 0xff), green = UInt8((tint >> 16) & 0xff)
        let blue = UInt8((tint >> 8) & 0xff), tintAlpha = UInt32(tint & 0xff)
        let originX = (targetWidth - Int(glyphWidth)) / 2
        let originY = (targetHeight - Int(glyphHeight)) / 2
        var nonZero: UInt32 = 0, maximum: UInt8 = 0
        // GDI glyph-outline buffers use bottom-up scanlines; ABI RGBA is top-down.
        for row in 0..<Int(glyphHeight) {
            let sourceRow = Int(glyphHeight) - 1 - row
            for column in 0..<Int(glyphWidth) {
                let targetX = originX + column, targetY = originY + row
                guard targetX >= 0, targetX < targetWidth, targetY >= 0, targetY < targetHeight else { continue }
                let gray = min(UInt32(bitmap[sourceRow * rowBytes + column]), 64)
                let coverage = UInt8((gray * 255 + 32) / 64)
                if coverage > 0 { nonZero += 1 }; maximum = max(maximum, coverage)
                let index = (targetY * targetWidth + targetX) * 4
                rgba[index] = red; rgba[index + 1] = green; rgba[index + 2] = blue
                rgba[index + 3] = UInt8((UInt32(coverage) * tintAlpha + 127) / 255)
            }
        }
        guard nonZero > 0 else { throw FactorySystemImageProviderError.emptyCoverage }
        return FactorySystemImageRaster(rgba: rgba, width: width, height: height,
            glyphWidth: glyphWidth, glyphHeight: glyphHeight, nonZeroCoverage: nonZero,
            maxCoverage: maximum, fontHeight: textMetrics.tmHeight,
            fontAscent: textMetrics.tmAscent, glyphOriginX: glyphMetrics.gmptGlyphOrigin.x,
            glyphOriginY: glyphMetrics.gmptGlyphOrigin.y, selectedFace: selectedFace)
    }
}
