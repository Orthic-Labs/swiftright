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

    func testBodyTextUsesTheLiveBodyProfile() throws {
        let m = try TextRequestAdapter.shapingRequest(for: req("+", width: 40), body: body, fonts: nil, scale: 2.5, textColor: 0x1f1f1fff)
        XCTAssertEqual(m.fontFamily, "Segoe UI"); XCTAssertEqual(m.fontSize, 12); XCTAssertEqual(m.lineHeight, 16); XCTAssertEqual(m.maxWidth, 100)
    }

    func testCustomFontResolvesThroughTheBundledLibraryWithCoreTextLineHeight() throws {
        let font = Font.custom("Tinos-Regular", size: 18)
        let m = try TextRequestAdapter.shapingRequest(for: req("SwiftRight", font: font, limit: 1, width: 128), body: body, fonts: FakeFonts(), scale: 2.5, textColor: 0x1f1f1fff)
        XCTAssertEqual(m.fontFamily, "Tinos"); XCTAssertEqual(m.fontSize, 18); XCTAssertEqual(m.lineHeight, 20); XCTAssertEqual(m.weight, 400)
        XCTAssertEqual(m.maxWidth, 320)
        let bold = try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Tinos", size: 18).weight(.bold)), body: body, fonts: FakeFonts(), scale: 1, textColor: 0)
        XCTAssertEqual(bold.weight, 700)
    }

    func testUnresolvableRequestsFailVisiblyInsteadOfFallingBack() {
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Nope", size: 12)), body: body, fonts: FakeFonts(), scale: 1, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .customFontNotBundled("Nope")) }
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: Font.custom("Tinos", size: 12)), body: body, fonts: nil, scale: 1, textColor: 0))
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", limit: 2), body: body, fonts: nil, scale: 1, textColor: 0)) {
            XCTAssertEqual($0 as? TextMeasureError, .unsupportedLineLimit(2)) }
        XCTAssertThrowsError(try TextRequestAdapter.shapingRequest(for: req("x", font: .system(size: 14, weight: .bold, design: .serif)), body: body, fonts: nil, scale: 1, textColor: 0))
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
            .multilineWithoutBound, .noCandidateFits]
        for e in all {
            let d = e.description
            XCTAssertTrue(d.hasPrefix("TextMeasure: "), d)
            XCTAssertEqual(String(describing: e), d)
            XCTAssertEqual("\(e)", d)
        }
        XCTAssertEqual(TextMeasureError.unsupportedFont("system(13)").description, "TextMeasure: unsupportedFont(system(13))")
    }
}
