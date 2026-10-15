import XCTest
@testable import SwiftRightHost

/// Block F1: the generated Mac font metric table loads and carries the spot values measured by factory/tools/font-metrics (macOS 27, offscreen NSHostingView).
final class FontMetricTableTests: XCTestCase {
    let table = FontMetricTable.shared

    func testLoadsAndNamesItsOrigin() {
        XCTAssertTrue(table.isLoaded)
        XCTAssertEqual(table.tool, "font-metrics-1")
        XCTAssertFalse(table.macOSBuild.isEmpty)
    }

    func testBody13() {
        XCTAssertEqual(table.system(size: 13, scale: 1), .init(height: 16, firstBaseline: 13, lastBaseline: 13, width: 105))
        // at scale 2.5 SwiftUI snaps the baseline to a device pixel: 33 px = 13.2 pt
        XCTAssertEqual(table.system(size: 13, scale: 2.5)?.height, 16)
        XCTAssertEqual(table.system(size: 13, scale: 2.5)?.firstBaseline, 13.2)
        XCTAssertEqual(table.style("body", scale: 2.5), table.system(size: 13, scale: 2.5))
        let ct = table.coreTextSystem(size: 13)
        XCTAssertEqual(ct?.ascent ?? 0, 12.5684, accuracy: 0.001)
        XCTAssertEqual(ct?.descent ?? 0, 2.7422, accuracy: 0.001)
        XCTAssertEqual(ct?.face, ".SFNS-Regular")
    }

    func testCaption2IsMediumOnTheMac() {
        XCTAssertEqual(table.styleFont("caption2")?.pointSize, 10)
        XCTAssertEqual(table.styleFont("caption2")?.postScript, ".SFNS-Medium")
        XCTAssertEqual(table.styleFont("caption")?.postScript, ".SFNS-Regular")
        XCTAssertEqual(table.style("caption2", scale: 1)?.height, 13)
        XCTAssertEqual(table.style("caption2", scale: 1), table.system(size: 10, weight: "medium", scale: 1))
    }

    func testTextStyleLineHeightsAtScale1() {
        let heights = ["largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption", "caption2"].map { table.style($0, scale: 1)?.height }
        XCTAssertEqual(heights, [31, 26, 21, 19, 16, 16, 15, 14, 13, 13, 13].map { Optional(Double($0)) })
    }

    func testEmphasizedWeightOfAStyle() {
        // .bold() on a text style is the style's emphasized weight, not .bold
        XCTAssertEqual(table.style("body", variant: "bold()", scale: 1), table.style("body", variant: "semibold", scale: 1))
        XCTAssertEqual(table.style("headline", variant: "bold()", scale: 1), table.style("headline", variant: "heavy", scale: 1))
        XCTAssertEqual(table.style("title", variant: "bold()", scale: 1), table.style("title", variant: "bold", scale: 1))
    }

    func testFontCustomLookupOrder() throws {
        let lookup = try XCTUnwrap(table.raw["lookup"] as? [String: Any])
        func resolved(_ name: String) -> String? { ((lookup[name] as? [String: Any])?["swiftUI@2.5"] as? [String: Any])?["resolved"] as? String }
        XCTAssertEqual(resolved("ZqCollide1"), "c1-ps")      // PostScript, full and family collide: PostScript wins
        XCTAssertEqual(resolved("ZqCollide4"), "c4-full")    // full name beats family
        XCTAssertEqual(resolved("Tinos"), "Tinos")
    }

    func testBundledSingleFaceIsNotSynthesised() throws {
        let syn = try XCTUnwrap(table.raw["synthesis"] as? [String: Any])
        func digest(_ k: String) -> String? { (syn[k] as? [String: Any])?["digest"] as? String }
        XCTAssertNotNil(digest("swiftUI|Tinos|regular"))
        XCTAssertEqual(digest("swiftUI|Tinos|bold()"), digest("swiftUI|Tinos|regular"))
        XCTAssertEqual(digest("swiftUI|Tinos|italic()"), digest("swiftUI|Tinos|regular"))
        XCTAssertNotEqual(digest("swiftUI|Helvetica|bold()"), digest("swiftUI|Helvetica|regular"))   // control: a family with a real bold face differs
    }

    func testMixedScriptLineKeepsTheBaseFontHeight() {
        for line in ["latin+ja", "latin+zh", "latin+ko", "latin+emoji", "all", "thai", "hindi", "arabic"] {
            XCTAssertEqual(table.mixedLine("system13|\(line)", scale: 1)?.height, 16, line)
            XCTAssertEqual(table.mixedLine("tinos20|\(line)", scale: 2.5)?.height, 22, line)
        }
    }
}
