import XCTest
import SwiftRightHost

final class FakeFonts: CustomFontResolving {
    func providerFamily(forCustomName name: String) -> String? { name.lowercased().hasPrefix("tinos") ? "Tinos" : nil }
    func metrics(forCustomName name: String) -> FontFileMetrics? {
        providerFamily(forCustomName: name) == nil ? nil : FontFileMetrics.parse(tinosLikeSfnt())
    }
}
func tinosLikeSfnt() -> [UInt8] {
    func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xff)] }
    func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    var head = [UInt8](repeating: 0, count: 54); head.replaceSubrange(18..<20, with: be16(2048))
    var hhea = [UInt8](repeating: 0, count: 36)
    hhea.replaceSubrange(4..<6, with: be16(1825)); hhea.replaceSubrange(6..<8, with: be16(UInt16(bitPattern: -443))); hhea.replaceSubrange(8..<10, with: be16(87))
    let dir = 12 + 32
    return be32(0x00010000) + be16(2) + [0, 0, 0, 0, 0, 0]
        + Array("head".utf8) + be32(0) + be32(UInt32(dir)) + be32(54) + Array("hhea".utf8) + be32(0) + be32(UInt32(dir + 54)) + be32(36) + head + hhea
}

final class TextRequestAdapterTests: XCTestCase {
    private let body = BodyFontProfile(family: "Segoe UI", weight: 400, fontSizeDIP: 12, lineHeightDIP: 16)
    private func req(_ text: String, font: Font? = nil, limit: Int? = nil, width: CGFloat? = nil) -> TextMeasureRequest {
        TextMeasureRequest(text: text, fontID: font?.id ?? "body", proposedWidth: width, scale: 2.5, fontMetadata: font?.metadata, lineLimit: limit)
    }

    func testBodyTextIs13DIPWithTheMacLineHeight() throws {
        // decision G40: body is 13 DIP point-for-point with the Mac, whatever the Windows message font profile says (12 DIP here)
        let m = try TextRequestAdapter.shapingRequest(for: req("+", width: 40), body: body, fonts: nil, scale: 2.5, textColor: 0x272727ff)
        XCTAssertEqual(m.fontFamily, "Segoe UI Variable Text"); XCTAssertEqual(m.fontSize, 13); XCTAssertEqual(m.lineHeight, 16); XCTAssertEqual(m.weight, 400); XCTAssertEqual(m.maxWidth, 100)
    }

    func testCustomFontResolvesThroughTheBundledLibraryWithCoreTextLineHeight() throws {
        let font = Font.custom("Tinos-Regular", size: 18)
        let m = try TextRequestAdapter.shapingRequest(for: req("SwiftRight", font: font, limit: 1, width: 128), body: body, fonts: FakeFonts(), scale: 2.5, textColor: 0x272727ff)
        XCTAssertEqual(m.fontFamily, "Tinos"); XCTAssertEqual(m.fontSize, 18); XCTAssertEqual(m.lineHeight, 20); XCTAssertEqual(m.weight, 400)
        XCTAssertEqual(m.maxWidth, 320)
        let bold = try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Tinos", size: 18).weight(.bold)), body: body, fonts: FakeFonts(), scale: 1, textColor: 0)
        XCTAssertEqual(bold.weight, 700)
    }

    func testUnresolvableRequestsFailVisiblyInsteadOfFallingBack() {
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Nope", size: 12)), body: body, fonts: FakeFonts(), scale: 1, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .customFontNotBundled("Nope")) }
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Tinos", size: 12)), body: body, fonts: nil, scale: 1, textColor: 0))
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", limit: 0), body: body, fonts: nil, scale: 1, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .unsupportedLineLimit(0)) }
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: .system(size: 14, weight: .bold, design: .serif)), body: body, fonts: nil, scale: 2, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .unsupportedScale(2)) }
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Tinos", size: 0)), body: body, fonts: FakeFonts(), scale: 1, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .invalidPointSize) }
    }
}

final class SingleLineTextTests: XCTestCase {
    private struct M { var text: String }
    private func run(_ text: String, maxWidth: Float, advance: Float = 10) throws -> (String, Int, [String]) {
        var released: [String] = []
        let s = try SingleLineText.select(text, maxWidth: maxWidth, measure: { M(text: $0) },
                                          width: { Float($0.text.count) * advance }, lineCount: { _ in 1 }, release: { released.append($0.text) })
        return (s.displayText, s.candidateCount, released)
    }
    func testFittingTextIsReturnedUntouched() throws { let r = try run("abc", maxWidth: 100); XCTAssertEqual(r.0, "abc"); XCTAssertEqual(r.2, []) }
    func testLongTextTruncatesToTheLongestFittingPrefixPlusEllipsis() throws {
        let r = try run(String(repeating: "x", count: 50), maxWidth: 100)
        XCTAssertEqual(r.0, String(repeating: "x", count: 9) + "\u{2026}")     // 10 characters * 10 = 100 fits
        XCTAssertLessThanOrEqual(r.1, 12)
    }
    func testUnboundedMultilineAndEmptyFailVisibly() {
        XCTAssertThrowsError(try SingleLineText.select("x", maxWidth: -1, measure: { M(text: $0) }, width: { _ in 0 }, lineCount: { _ in 1 }, release: { _ in }))
        XCTAssertThrowsError(try SingleLineText.select("xx", maxWidth: 0, measure: { M(text: $0) }, width: { _ in 0 }, lineCount: { _ in 2 }, release: { _ in })) {
            XCTAssertEqual($0 as? TextMeasureError, .multilineWithoutBound) }
        XCTAssertThrowsError(try SingleLineText.select("xxxxxx", maxWidth: 5, measure: { M(text: $0) }, width: { _ in 99 }, lineCount: { _ in 1 }, release: { _ in })) {
            XCTAssertEqual($0 as? TextMeasureError, .noCandidateFits) }
        XCTAssertThrowsError(try SingleLineText.select(String(repeating: "x", count: 5000), maxWidth: 5, measure: { M(text: $0) }, width: { _ in 99 }, lineCount: { _ in 1 }, release: { _ in })) {
            XCTAssertEqual($0 as? TextMeasureError, .sourceTooLong) }
    }
}

/// `TextMeasureError.description` once interpolated `self` and called itself: the first measurement failure overflowed the stack.
final class TextMeasureErrorDescriptionTests: XCTestCase {
    func testEveryCaseDescribesItselfWithoutRecursing() {
        let all: [TextMeasureError] = [.unsupportedFont("system(13)"), .unsupportedLineLimit(3), .customFontNotBundled("Tanker"),
            .customFontMetricsUnavailable("Tanker"), .invalidPointSize, .measurementCacheBound, .sourceTooLong, .invalidWidth,
            .multilineWithoutBound, .noCandidateFits, .unsupportedScale(2), .systemFontMetricsUnavailable("size 8")]
        for e in all {
            let d = e.description
            XCTAssertTrue(d.hasPrefix("TextMeasure: "), d)
            XCTAssertEqual(String(describing: e), d)
            XCTAssertEqual("\(e)", d)
        }
        XCTAssertEqual(TextMeasureError.unsupportedFont("system(13)").description, "TextMeasure: unsupportedFont(system(13))")
    }
}


/// Round 5, block swiftui.system-font, rewritten by F2 (decisions G40, G70+): `Font.system(size:weight:)` and the text styles reach the shaper as a Segoe UI Variable
/// family at the requested size and weight with the Mac's line height from the F1 table. The full F2 matrix is in `SystemFontMappingTests`.
final class SystemFontAdapterTests: XCTestCase {
    private let body = BodyFontProfile(family: "Segoe UI", weight: 400, fontSizeDIP: 12, lineHeightDIP: 16, ascentEm: 2210.0 / 2048, descentEm: 514.0 / 2048)
    private func req(_ font: Font, text: String = "Overview", limit: Int? = nil, width: CGFloat? = nil, scale: CGFloat = 2.5) -> TextMeasureRequest {
        TextMeasureRequest(text: text, fontID: font.id, proposedWidth: width, scale: scale, fontMetadata: font.metadata, lineLimit: limit)
    }
    private func shape(_ font: Font, limit: Int? = nil, width: CGFloat? = nil, scale: Float = 2.5) throws -> MeasureRequest {
        try TextRequestAdapter.shapingRequest(for: req(font, limit: limit, width: width, scale: CGFloat(scale)), body: body, fonts: nil, scale: scale, textColor: 0x272727ff)
    }

    func testSystemFontIsASegoeVariableFamilyAtTheRequestedSizeAndWeightWithTheMacLine() throws {
        let m = try shape(Font.system(size: 18, weight: .semibold))
        XCTAssertEqual(m.fontFamily, "Segoe UI Variable Text"); XCTAssertEqual(m.fontSize, 18); XCTAssertEqual(m.weight, 600)
        XCTAssertEqual(m.lineHeight, Float(FontMetricTable.shared.system(size: 18, scale: 1)!.height))   // the Mac table's scale-1 height (the G75b pitch; 21.2 DIP single line at 2.5 = round(21 x 2.5) px), not round(ascent) + round(descent)
        XCTAssertEqual(try shape(Font.system(size: 11.5)).fontSize, 11.5)
        XCTAssertEqual(try shape(Font.system(size: 11.5)).fontFamily, "Segoe UI Variable Small")
        XCTAssertEqual(try shape(Font.system(size: 12)).weight, 400)
        XCTAssertEqual(try shape(Font.system(size: 12, weight: .regular).weight(.heavy)).weight, 900)   // static Segoe UI Black, reported adapted
    }

    func testTextStylesAreThePointForPointMacSizes() throws {
        let b = try shape(.body)
        XCTAssertEqual(b.fontSize, 13); XCTAssertEqual(b.lineHeight, 16)
        XCTAssertEqual(try shape(.title).fontSize, 22); XCTAssertEqual(try shape(.title).weight, 400)   // no 12/13 scaling any more
        XCTAssertEqual(try shape(.headline).weight, 700)
        XCTAssertEqual(try shape(.headline.weight(.regular)).weight, 400)
        XCTAssertEqual(try shape(.caption).fontSize, 10)
        XCTAssertEqual(try shape(.body.weight(.bold)).weight, 700)
        XCTAssertEqual(try shape(.body.weight(.bold)).fontSize, 13)
    }

    func testWidthIsCarriedAndDrawsAlike() throws {
        XCTAssertEqual(try shape(Font.system(size: 14, weight: .semibold).width(.expanded)).fontSize, 14)
        XCTAssertNotEqual(Font.system(size: 14).width(.expanded), Font.system(size: 14))
    }

    func testDesignsAreMappedNotRefused() throws {
        XCTAssertEqual(try shape(Font.system(size: 14, weight: .regular, design: .monospaced)).fontFamily, "Cascadia Mono")
        XCTAssertEqual(try shape(Font.system(size: 14, weight: .regular, design: .serif)).fontFamily, "Sitka Text")
        XCTAssertEqual(try shape(Font.system(size: 14, weight: .regular, design: .rounded)).fontFamily, "Segoe UI Variable Text")
        XCTAssertNoThrow(try shape(Font.system(size: 14, weight: .regular, design: .default)))
        XCTAssertThrowsError(try shape(Font.system(size: 0)))
        XCTAssertThrowsError(try shape(Font.system(size: 1000)))
        XCTAssertThrowsError(try shape(Font.system(size: 8))) { XCTAssertTrue(String(describing: $0).contains("systemFontMetricsUnavailable")) }   // outside the measured 9 to 40 pt
    }

    func testLineLimitAboveOneIsAccepted() throws {
        XCTAssertNoThrow(try shape(Font.system(size: 12), limit: 3, width: 100))
    }
}

private extension Double { var asFloat: Float { Float(self) } }

final class MultiLineTextTests: XCTestCase {
    private struct M { var text: String }
    /// 10 per character, lines of at most `perLine` characters, broken anywhere.
    private func select(_ text: String, perLine: Int, limit: Int) throws -> String {
        try SingleLineText.select(text, maxWidth: Float(perLine * 10), lineLimit: limit, measure: { M(text: $0) },
                                  width: { Float(min($0.text.count, perLine) * 10) }, lineCount: { max(1, ($0.text.count + perLine - 1) / perLine) }, release: { _ in }).displayText
    }
    func testTextThatFitsTheLineLimitIsUntouched() throws {
        XCTAssertEqual(try select("abcdefghij", perLine: 5, limit: 2), "abcdefghij")
    }
    func testTextOverTheLineLimitEndsInAnEllipsisOnTheLastLine() throws {
        XCTAssertEqual(try select("abcdefghijklmnop", perLine: 5, limit: 2), "abcdefghi\u{2026}")   // 9 characters + the ellipsis = 10 = two lines of 5
        XCTAssertEqual(try select("abcdefghijklmnop", perLine: 5, limit: 3), "abcdefghijklmn\u{2026}")
        XCTAssertEqual(try select("abcdefghijklmnop", perLine: 5, limit: 1), "abcd\u{2026}")
    }
}

/// #51: `.lineLimit(n)` rides the renderer's SWR_M08_MAX_LINES; the host search is only the fallback.
final class NativeLineLimitTests: XCTestCase {
    private struct M { var tag: String; var applied: Bool }
    private func base() -> MeasureRequest { MeasureRequest(text: "hello world", fontFamily: "Tinos", fontSize: 18, lineHeight: 20, scale: 2.5, maxWidth: 100) }

    func testRequestCarriesTheLimitOnlyInRange() {
        XCTAssertEqual(NativeLineLimit.request(base(), limit: 1)?.maxLines, 1)
        XCTAssertEqual(NativeLineLimit.request(base(), limit: 1000)?.maxLines, 1000)
        XCTAssertNil(NativeLineLimit.request(base(), limit: 0))
        XCTAssertNil(NativeLineLimit.request(base(), limit: 1001))
        XCTAssertNil(base().maxLines, "an unlimited request is unchanged")
    }

    func testNativeResultWinsWhenTheRendererReportsApplied() throws {
        var seen: [Int?] = [], released = 0, fell = 0
        let r = try NativeLineLimit.shape(base(), limit: 1, rendererSupportsMaxLines: true,
            native: { seen.append($0.maxLines); return M(tag: "native", applied: true) }, applied: { $0.applied },
            release: { _ in released += 1 }, fallback: { fell += 1; return M(tag: "host", applied: false) })
        XCTAssertEqual(r.measurement.tag, "native"); XCTAssertTrue(r.native)
        XCTAssertEqual(seen, [1]); XCTAssertEqual(released, 0); XCTAssertEqual(fell, 0)
    }

    func testFallsBackWhenNotAppliedUnsupportedOrRefused() throws {
        var released: [String] = []
        func run(support: Bool, limit: Int = 1, native: @escaping (MeasureRequest) throws -> M) throws -> (M, Bool) {
            try NativeLineLimit.shape(base(), limit: limit, rendererSupportsMaxLines: support, native: native, applied: { $0.applied },
                                      release: { released.append($0.tag) }, fallback: { M(tag: "host", applied: false) })
        }
        let old = try run(support: true) { _ in M(tag: "old-renderer", applied: false) }
        XCTAssertEqual(old.0.tag, "host"); XCTAssertFalse(old.1); XCTAssertEqual(released, ["old-renderer"], "the unapplied run is released")
        var calls = 0
        let none = try run(support: false) { _ in calls += 1; return M(tag: "n", applied: true) }
        XCTAssertEqual(none.0.tag, "host"); XCTAssertEqual(calls, 0, "no 0.8 extension: the request is never sent")
        let big = try run(support: true, limit: 5000) { _ in calls += 1; return M(tag: "n", applied: true) }
        XCTAssertEqual(big.0.tag, "host"); XCTAssertEqual(calls, 0)
        struct Refused: Error {}
        let refused = try run(support: true) { _ in throw Refused() }
        XCTAssertEqual(refused.0.tag, "host")
    }
}
