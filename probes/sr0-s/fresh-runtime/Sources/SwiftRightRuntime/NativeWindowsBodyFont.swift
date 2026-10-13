import Foundation
#if os(Windows)
import WinSDK
#endif

/// Live Windows `Font.body` profile resolved from current DPI-aware system
/// message-font settings. Runtime clients pass returned values through existing
/// text measurement APIs; no Apple-specific target metrics are embedded here.
public struct NativeWindowsBodyFont: Equatable, Sendable {
    public let family: String
    public let fontSizeDIP: Float
    public let lineHeightDIP: Float
    public let weight: UInt32
    public let logFontHeight: Int32
    public let textMetricHeight: Int32
    public let textMetricAscent: Int32
    public let textMetricDescent: Int32
    public let textMetricExternalLeading: Int32
    public let dpi: UInt32
    public let sourceAPI: String

    public init(family: String, fontSizeDIP: Float, lineHeightDIP: Float,
                weight: UInt32, logFontHeight: Int32,
                textMetricHeight: Int32, textMetricAscent: Int32,
                textMetricDescent: Int32, textMetricExternalLeading: Int32,
                dpi: UInt32, sourceAPI: String) {
        self.family = family
        self.fontSizeDIP = fontSizeDIP
        self.lineHeightDIP = lineHeightDIP
        self.weight = weight
        self.logFontHeight = logFontHeight
        self.textMetricHeight = textMetricHeight
        self.textMetricAscent = textMetricAscent
        self.textMetricDescent = textMetricDescent
        self.textMetricExternalLeading = textMetricExternalLeading
        self.dpi = dpi
        self.sourceAPI = sourceAPI
    }
}

public enum NativeWindowsBodyFontError: Error, Equatable {
    case invalidDPI
    case systemParametersUnavailable
    case invalidMessageFont
    case deviceContextUnavailable
    case fontUnavailable
    case fontSelectionUnavailable
    case selectedFaceUnavailable
    case textMetricsUnavailable
    case invalidMetrics
    case windowsOnly
}

/// Resolves live Windows default body-font metadata. Resolution is isolated in
/// runtime so every host uses same profile policy & retains real font identity.
public enum NativeWindowsBodyFontResolver {
    public static func resolve(dpi: UInt32, emitLog: Bool = true) throws -> NativeWindowsBodyFont {
        guard dpi >= 48, dpi <= 768 else { throw NativeWindowsBodyFontError.invalidDPI }
#if os(Windows)
        let scale = Float(dpi) / 96
        var nonClient = NONCLIENTMETRICSW()
        let nonClientSize = UInt32(MemoryLayout<NONCLIENTMETRICSW>.size)
        nonClient.cbSize = nonClientSize
        let parametersOK = withUnsafeMutablePointer(to: &nonClient) { pointer in
            SystemParametersInfoForDpi(UInt32(0x0029), nonClientSize,
                                       UnsafeMutableRawPointer(pointer), UInt32(0), dpi)
        }
        guard parametersOK else { throw NativeWindowsBodyFontError.systemParametersUnavailable }

        var logFont = nonClient.lfMessageFont
        let rawHeight = Int64(logFont.lfHeight)
        guard rawHeight != 0 else { throw NativeWindowsBodyFontError.invalidMessageFont }
        let fontHeightPixels = abs(rawHeight)
        guard let dc = CreateCompatibleDC(nil) else {
            throw NativeWindowsBodyFontError.deviceContextUnavailable
        }
        defer { _ = DeleteDC(dc) }
        guard let font = withUnsafePointer(to: &logFont, { CreateFontIndirectW($0) }) else {
            throw NativeWindowsBodyFontError.fontUnavailable
        }
        defer { _ = DeleteObject(font) }
        guard let previous = SelectObject(dc, font) else {
            throw NativeWindowsBodyFontError.fontSelectionUnavailable
        }
        defer { _ = SelectObject(dc, previous) }

        var faceBuffer = [WCHAR](repeating: 0, count: 256)
        let faceLength = faceBuffer.withUnsafeMutableBufferPointer { buffer -> Int32 in
            GetTextFaceW(dc, Int32(buffer.count), buffer.baseAddress)
        }
        guard faceLength > 0, faceLength < Int32(faceBuffer.count) else {
            throw NativeWindowsBodyFontError.selectedFaceUnavailable
        }
        let selectedFace = String(decoding: faceBuffer.prefix(Int(faceLength)).prefix(while: { $0 != 0 }), as: UTF16.self)
        guard !selectedFace.isEmpty else { throw NativeWindowsBodyFontError.selectedFaceUnavailable }

        var textMetrics = TEXTMETRICW()
        guard GetTextMetricsW(dc, &textMetrics) else {
            throw NativeWindowsBodyFontError.textMetricsUnavailable
        }
        guard textMetrics.tmHeight > 0, textMetrics.tmAscent >= 0, textMetrics.tmDescent >= 0 else {
            throw NativeWindowsBodyFontError.invalidMetrics
        }
        let fontSizeDIP = Float(fontHeightPixels) / scale
        let lineHeightDIP = Float(textMetrics.tmHeight) / scale
        guard fontSizeDIP.isFinite, fontSizeDIP > 0,
              lineHeightDIP.isFinite, lineHeightDIP > 0 else {
            throw NativeWindowsBodyFontError.invalidMetrics
        }
        let weight = UInt32(max(0, min(Int64(logFont.lfWeight), Int64(UInt32.max))))
        let sourceAPI = "SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS)+CreateFontIndirectW+GetTextMetricsW"
        if emitLog {
            print("FACTORY_BODY_FONT_POLICY api=\(sourceAPI) family=\(selectedFace) dpi=\(dpi) lfHeight=\(logFont.lfHeight) fontSizeDIP=\(fontSizeDIP) tmHeightPX=\(textMetrics.tmHeight) tmAscentPX=\(textMetrics.tmAscent) tmDescentPX=\(textMetrics.tmDescent) tmExternalLeadingPX=\(textMetrics.tmExternalLeading) lineHeightDIP=\(lineHeightDIP) weight=\(weight) scale=\(scale)")
        }
        return NativeWindowsBodyFont(family: selectedFace, fontSizeDIP: fontSizeDIP,
                                     lineHeightDIP: lineHeightDIP, weight: weight,
                                     logFontHeight: logFont.lfHeight,
                                     textMetricHeight: textMetrics.tmHeight,
                                     textMetricAscent: textMetrics.tmAscent,
                                     textMetricDescent: textMetrics.tmDescent,
                                     textMetricExternalLeading: textMetrics.tmExternalLeading,
                                     dpi: dpi, sourceAPI: sourceAPI)
#else
        _ = emitLog
        throw NativeWindowsBodyFontError.windowsOnly
#endif
    }
}
