#if os(Windows)
import Foundation
import WinSDK

/// Request for one live Windows system-image glyph.
public struct WindowsSystemImageGlyphRequest: Sendable {
    public let providerFamily: String
    public let glyph: UInt32
    public let targetWidth: UInt32
    public let targetHeight: UInt32

    public init(providerFamily: String,
                glyph: UInt32,
                targetWidth: UInt32,
                targetHeight: UInt32) {
        self.providerFamily = providerFamily
        self.glyph = glyph
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
    }
}

/// Native grayscale coverage plus selected-face & cell metrics. Coverage is
/// deliberately separate from RGBA composition so ABI registration stays in
/// host code while native provider identity remains observable.
public struct WindowsSystemImageGlyphCoverage: Sendable {
    public let sourceWidth: UInt32
    public let sourceHeight: UInt32
    public let rowBytes: UInt32
    public let coverage: [UInt8]
    public let coverageMaximum: UInt8
    public let rowOrder: SystemImageRasterRowOrder
    public let selectedFace: String
    public let averageCharWidth: Int32
    public let cellIncrementX: Int32
    public let cellIncrementY: Int32
    public let fontHeight: Int32
    public let fontAscent: Int32
    public let glyphOriginX: Int32
    public let glyphOriginY: Int32

    public init(sourceWidth: UInt32,
                sourceHeight: UInt32,
                rowBytes: UInt32,
                coverage: [UInt8],
                coverageMaximum: UInt8,
                rowOrder: SystemImageRasterRowOrder,
                selectedFace: String,
                averageCharWidth: Int32,
                cellIncrementX: Int32,
                cellIncrementY: Int32,
                fontHeight: Int32,
                fontAscent: Int32,
                glyphOriginX: Int32,
                glyphOriginY: Int32) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.rowBytes = rowBytes
        self.coverage = coverage
        self.coverageMaximum = coverageMaximum
        self.rowOrder = rowOrder
        self.selectedFace = selectedFace
        self.averageCharWidth = averageCharWidth
        self.cellIncrementX = cellIncrementX
        self.cellIncrementY = cellIncrementY
        self.fontHeight = fontHeight
        self.fontAscent = fontAscent
        self.glyphOriginX = glyphOriginX
        self.glyphOriginY = glyphOriginY
    }
}

public enum WindowsSystemImageProviderError: Error, Equatable, Sendable {
    case invalidRequest
    case deviceContextUnavailable
    case fontUnavailable
    case selectedFaceMismatch
    case metricsUnavailable
    case glyphUnavailable
    case coverageUnavailable
}

/// Bounded GDI provider for declared Windows glyph mappings. CreateFontW may
/// substitute silently, so GetTextFaceW must equal requested family exactly.
public enum WindowsSystemImageProvider {
    private static let maxDimension: UInt32 = 4096
    private static let maxBufferBytes: UInt64 = 16 * 1024 * 1024

    /// GetTextFaceW reports copied UTF-16 characters, while Windows builds
    /// differ on whether reported length includes trailing NUL. Decode from
    /// buffer termination, then let caller retain exact family matching.
    internal static func decodeSelectedFace(_ buffer: [UInt16], reportedLength: Int32) -> String? {
        guard reportedLength > 0, Int(reportedLength) < buffer.count else { return nil }
        let reportedLimit = Int(reportedLength) + 1
        guard let nul = buffer.prefix(reportedLimit).firstIndex(of: 0), nul > 0 else {
            return nil
        }
        return String(decoding: buffer.prefix(nul), as: UTF16.self)
    }

    public static func rasterize(_ request: WindowsSystemImageGlyphRequest) throws -> WindowsSystemImageGlyphCoverage {
        guard !request.providerFamily.isEmpty, request.providerFamily.utf8.count <= 128,
              request.glyph <= 0x10ffff,
              request.targetWidth > 0, request.targetHeight > 0,
              request.targetWidth <= maxDimension, request.targetHeight <= maxDimension,
              UInt64(request.targetWidth) * UInt64(request.targetHeight) * 4 <= maxBufferBytes else {
            throw WindowsSystemImageProviderError.invalidRequest
        }
        guard let dc = CreateCompatibleDC(nil) else {
            throw WindowsSystemImageProviderError.deviceContextUnavailable
        }
        defer { _ = DeleteDC(dc) }
        let fontHeight = Int32(max(request.targetWidth, request.targetHeight))
        var units = Array(request.providerFamily.utf16) + [0]
        let font: HFONT? = units.withUnsafeBufferPointer { family in
            CreateFontW(-fontHeight, 0, 0, 0, Int32(FW_NORMAL), 0, 0, 0,
                        UINT32(DEFAULT_CHARSET), UINT32(OUT_DEFAULT_PRECIS),
                        UINT32(CLIP_DEFAULT_PRECIS), UINT32(CLEARTYPE_QUALITY),
                        UINT32(DEFAULT_PITCH | FF_DONTCARE), family.baseAddress!)
        }
        guard let font else { throw WindowsSystemImageProviderError.fontUnavailable }
        defer { _ = DeleteObject(font) }
        guard let previous = SelectObject(dc, font) else {
            throw WindowsSystemImageProviderError.fontUnavailable
        }
        defer { _ = SelectObject(dc, previous) }

        var faceBuffer = [UInt16](repeating: 0, count: 256)
        let faceLength = faceBuffer.withUnsafeMutableBufferPointer { buffer -> Int32 in
            GetTextFaceW(dc, Int32(buffer.count), buffer.baseAddress)
        }
        guard faceLength > 0, faceLength < Int32(faceBuffer.count) else {
            throw WindowsSystemImageProviderError.selectedFaceMismatch
        }
        guard let selectedFace = decodeSelectedFace(faceBuffer, reportedLength: faceLength),
              selectedFace == request.providerFamily else {
            throw WindowsSystemImageProviderError.selectedFaceMismatch
        }

        var textMetrics = TEXTMETRICW()
        guard GetTextMetricsW(dc, &textMetrics) else {
            throw WindowsSystemImageProviderError.metricsUnavailable
        }
        let fixedOne = FIXED(fract: 0, value: 1)
        let fixedZero = FIXED(fract: 0, value: 0)
        var transform = MAT2(eM11: fixedOne, eM12: fixedZero, eM21: fixedZero, eM22: fixedOne)
        var glyphMetrics = GLYPHMETRICS()
        let required = GetGlyphOutlineW(dc, request.glyph, UINT32(GGO_GRAY8_BITMAP), &glyphMetrics,
                                        0, nil, &transform)
        guard required != UInt32(GDI_ERROR), required > 0 else {
            throw WindowsSystemImageProviderError.glyphUnavailable
        }
        let sourceWidth = UInt32(glyphMetrics.gmBlackBoxX)
        let sourceHeight = UInt32(glyphMetrics.gmBlackBoxY)
        guard sourceWidth > 0, sourceHeight > 0,
              sourceWidth <= maxDimension, sourceHeight <= maxDimension else {
            throw WindowsSystemImageProviderError.coverageUnavailable
        }
        let rowBytes = (Int(sourceWidth) + 3) & ~3
        let expectedBytes = UInt64(rowBytes) * UInt64(sourceHeight)
        guard expectedBytes <= maxBufferBytes,
              UInt64(required) <= maxBufferBytes,
              expectedBytes <= UInt64(required) else {
            throw WindowsSystemImageProviderError.coverageUnavailable
        }
        var coverage = Array(repeating: UInt8(0), count: Int(required))
        let rendered = coverage.withUnsafeMutableBytes { raw in
            GetGlyphOutlineW(dc, request.glyph, UINT32(GGO_GRAY8_BITMAP), &glyphMetrics,
                             required, raw.baseAddress, &transform)
        }
        guard rendered == required else { throw WindowsSystemImageProviderError.coverageUnavailable }
        guard coverage[0..<Int(expectedBytes)].contains(where: { $0 > 0 }) else {
            throw WindowsSystemImageProviderError.coverageUnavailable
        }

        return WindowsSystemImageGlyphCoverage(
            sourceWidth: sourceWidth, sourceHeight: sourceHeight, rowBytes: UInt32(rowBytes),
            coverage: coverage, coverageMaximum: 64, rowOrder: .topDown,
            selectedFace: selectedFace, averageCharWidth: textMetrics.tmAveCharWidth,
            cellIncrementX: Int32(glyphMetrics.gmCellIncX), cellIncrementY: Int32(glyphMetrics.gmCellIncY),
            fontHeight: textMetrics.tmHeight,
            fontAscent: textMetrics.tmAscent, glyphOriginX: glyphMetrics.gmptGlyphOrigin.x,
            glyphOriginY: glyphMetrics.gmptGlyphOrigin.y)
    }
}
#endif
