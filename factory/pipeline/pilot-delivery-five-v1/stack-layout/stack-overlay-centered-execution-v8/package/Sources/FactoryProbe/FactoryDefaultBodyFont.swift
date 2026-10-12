import Foundation
import WinSDK

struct FactoryDefaultBodyFontPolicy {
    let family: String
    let fontSizeDIP: Float
    let lineHeightDIP: Float
    let weight: UInt32
    let logFontHeight: Int32
    let textMetricHeight: Int32
    let textMetricAscent: Int32
    let textMetricDescent: Int32
    let textMetricExternalLeading: Int32
    let sourceAPI: String
}

enum FactoryDefaultBodyFontError: Error {
    case invalidScale
    case systemParametersUnavailable
    case invalidMessageFont
    case deviceContextUnavailable
    case fontUnavailable
    case fontSelectionUnavailable
    case selectedFaceUnavailable
    case textMetricsUnavailable
    case invalidMetrics
}

/// Resolves Font.body from Windows' current message-font profile, then measures
/// that selected font through GDI. No Mac target size or family is substituted.
func factoryDefaultBodyFontPolicy(dpi: UInt32) throws -> FactoryDefaultBodyFontPolicy {
    guard dpi >= 48, dpi <= 768 else {
        throw FactoryDefaultBodyFontError.invalidScale
    }
    let scale = Float(dpi) / 96

    var nonClient = NONCLIENTMETRICSW()
    nonClient.cbSize = UInt32(MemoryLayout<NONCLIENTMETRICSW>.size)
    let parametersOK = withUnsafeMutablePointer(to: &nonClient) { pointer in
        SystemParametersInfoForDpi(UInt32(0x0029), nonClient.cbSize,
                                   UnsafeMutableRawPointer(pointer), UInt32(0), dpi)
    }
    guard parametersOK else { throw FactoryDefaultBodyFontError.systemParametersUnavailable }

    var logFont = nonClient.lfMessageFont
    let rawHeight = Int64(logFont.lfHeight)
    guard rawHeight != 0 else { throw FactoryDefaultBodyFontError.invalidMessageFont }
    let fontHeightPixels = abs(rawHeight)

    guard let dc = CreateCompatibleDC(nil) else {
        throw FactoryDefaultBodyFontError.deviceContextUnavailable
    }
    defer { _ = DeleteDC(dc) }

    guard let font = withUnsafePointer(to: &logFont, { CreateFontIndirectW($0) }) else {
        throw FactoryDefaultBodyFontError.fontUnavailable
    }
    defer { _ = DeleteObject(font) }
    guard let previous = SelectObject(dc, font) else {
        throw FactoryDefaultBodyFontError.fontSelectionUnavailable
    }
    defer { _ = SelectObject(dc, previous) }

    var faceBuffer = [WCHAR](repeating: 0, count: 256)
    let faceLength = faceBuffer.withUnsafeMutableBufferPointer { buffer -> Int32 in
        GetTextFaceW(dc, Int32(buffer.count), buffer.baseAddress)
    }
    guard faceLength > 0, faceLength < Int32(faceBuffer.count) else {
        throw FactoryDefaultBodyFontError.selectedFaceUnavailable
    }
    let selectedFace = String(decoding: faceBuffer.prefix(Int(faceLength)).prefix(while: { $0 != 0 }), as: UTF16.self)
    guard !selectedFace.isEmpty else { throw FactoryDefaultBodyFontError.selectedFaceUnavailable }

    var textMetrics = TEXTMETRICW()
    guard GetTextMetricsW(dc, &textMetrics) else {
        throw FactoryDefaultBodyFontError.textMetricsUnavailable
    }
    guard textMetrics.tmHeight > 0, textMetrics.tmAscent >= 0, textMetrics.tmDescent >= 0 else {
        throw FactoryDefaultBodyFontError.invalidMetrics
    }

    // NONCLIENTMETRICS gives selected logical font height; TEXTMETRICW gives
    // actual selected-font cell metrics. Convert native pixels through window DPI.
    let fontSizeDIP = Float(fontHeightPixels) / scale
    let lineHeightDIP = Float(textMetrics.tmHeight) / scale
    guard fontSizeDIP.isFinite, fontSizeDIP > 0,
          lineHeightDIP.isFinite, lineHeightDIP > 0 else {
        throw FactoryDefaultBodyFontError.invalidMetrics
    }
    let weight = UInt32(max(0, min(Int64(logFont.lfWeight), Int64(UInt32.max))))
    print("FACTORY_BODY_FONT_POLICY api=SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS)+CreateFontIndirectW+GetTextMetricsW family=\(selectedFace) dpi=\(dpi) lfHeight=\(logFont.lfHeight) fontSizeDIP=\(fontSizeDIP) tmHeightPX=\(textMetrics.tmHeight) tmAscentPX=\(textMetrics.tmAscent) tmDescentPX=\(textMetrics.tmDescent) tmExternalLeadingPX=\(textMetrics.tmExternalLeading) lineHeightDIP=\(lineHeightDIP) weight=\(weight) scale=\(scale)")
    return FactoryDefaultBodyFontPolicy(
        family: selectedFace,
        fontSizeDIP: fontSizeDIP,
        lineHeightDIP: lineHeightDIP,
        weight: weight,
        logFontHeight: logFont.lfHeight,
        textMetricHeight: textMetrics.tmHeight,
        textMetricAscent: textMetrics.tmAscent,
        textMetricDescent: textMetrics.tmDescent,
        textMetricExternalLeading: textMetrics.tmExternalLeading,
        sourceAPI: "SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS)+CreateFontIndirectW+GetTextMetricsW"
    )
}
