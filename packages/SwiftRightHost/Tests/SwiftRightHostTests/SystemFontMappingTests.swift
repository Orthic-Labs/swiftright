import XCTest
import SwiftRightRuntime
import SwiftRightBridge
@testable import SwiftRightHost

/// Block F2 (decisions G40, G70+): system font mapping. Pure logic, no renderer: tables, plans, adapted-entry reports, scale refusal.
final class SystemFontMappingTests: XCTestCase {
    private let table = FontMetricTable.shared
    private let mapper = SystemFontMapper()
    private let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]

    private func plan(_ font: Font, scale: Float = 2.5, availability: SystemFontAvailability = .windows11) throws -> SystemFontPlan {
        try SystemFontMapper(availability: availability).plan(for: font.metadata, scale: scale)
    }

    // MARK: text styles

    func testElevenStylesHaveTheMacSizesAndWeights() throws {
        let expected: [(String, Float, UInt32)] = [("largeTitle", 26, 400), ("title", 22, 400), ("title2", 17, 400), ("title3", 15, 400), ("headline", 13, 700),
                                                    ("body", 13, 400), ("callout", 12, 400), ("subheadline", 11, 400), ("footnote", 10, 400), ("caption", 10, 400),
                                                    ("caption2", 10, 600)]   // caption2 is Medium on the Mac (G24); Windows has no 500: Semibold, reported
        XCTAssertEqual(expected.map { $0.0 }, MacTextStyles.names)
        for (name, size, weight) in expected {
            let p = try plan(Font(styleNamed: name))
            XCTAssertEqual(p.sizeDIP, size, name); XCTAssertEqual(p.weight, weight, name); XCTAssertEqual(p.textStyle, name)
        }
        XCTAssertEqual(MacTextStyles.all["caption2"]?.weight, .medium)
    }

    func testStyleTableAgreesWithTheMacCoreTextStyleInfo() throws {
        for name in MacTextStyles.names {
            XCTAssertEqual(Double(MacTextStyles.all[name]!.size), table.styleFont(name)?.pointSize, name)
        }
    }

    func testOneLineHeightsAtScale1AreTheMeasuredMacNumbers() throws {
        // largeTitle, title2 and title3 are 1 pt below the HIG, as measured (G23)
        let heights = try MacTextStyles.names.map { try plan(Font(styleNamed: $0), scale: 1).lineHeightDIP }
        XCTAssertEqual(heights, [31, 26, 21, 19, 16, 16, 15, 14, 13, 13, 13])
    }

    func testStylePlansEqualTheTableAtBothScales() throws {
        for scale in [Float(1), 2.5] {
            for name in MacTextStyles.names {
                let row = try XCTUnwrap(table.style(name, scale: Double(scale)))
                let p = try plan(Font(styleNamed: name), scale: scale)
                XCTAssertEqual(Double(p.lineHeightDIP), row.height, accuracy: 1e-5, "\(name)@\(scale)")
                XCTAssertEqual(Double(p.firstBaselineDIP), row.firstBaseline, accuracy: 1e-5, "\(name)@\(scale)")
                // a whole number of device pixels, so the retained run's snapped bounds equal the table's frame
                XCTAssertEqual(Double(p.lineHeightDIP * scale), Double(p.lineHeightDIP * scale).rounded(), accuracy: 1e-4)
                XCTAssertEqual(Double(p.firstBaselineDIP * scale), Double(p.firstBaselineDIP * scale).rounded(), accuracy: 1e-4)
            }
        }
        XCTAssertEqual(try plan(.largeTitle, scale: 2.5).lineHeightDIP, 30.8)   // device-pixel snapped: 77 px
        XCTAssertEqual(try plan(.body, scale: 2.5).firstBaselineDIP, 13.2)
    }

    func testBodyWithNoFontIsTheBodyStyleAt13DIP() throws {
        let none = try mapper.plan(for: nil, scale: 2.5)
        let body = try plan(.body)
        XCTAssertEqual(none, body)
        XCTAssertEqual(none.sizeDIP, 13); XCTAssertEqual(none.weight, 400); XCTAssertEqual(none.family, "Segoe UI Variable Text"); XCTAssertEqual(none.lineHeightDIP, 16)
    }

    func testBoldOnATextStyleIsTheEmphasizedWeightNotBold() throws {
        // G25: largeTitle, title, title2 bold; title3, subheadline, body, callout, footnote, caption2 semibold; caption medium; headline heavy
        let expected: [String: Font.Weight] = ["largeTitle": .bold, "title": .bold, "title2": .bold, "title3": .semibold, "subheadline": .semibold, "body": .semibold, "callout": .semibold,
                                               "footnote": .semibold, "caption2": .semibold, "caption": .medium, "headline": .heavy]
        for (name, w) in expected {
            XCTAssertEqual(MacTextStyles.all[name]?.emphasized, w, name)
            // the table's own bold() row has the same frame as that weight's row (G25), so the weights above are the measured ones
            XCTAssertEqual(table.style(name, variant: "bold()", scale: 1), table.style(name, variant: w.rawValue, scale: 1), name)
            let p = try plan(Font(styleNamed: name).bold())
            XCTAssertEqual(p.weight, WeightMapping.segoeVariable(w).weight, name)
        }
        XCTAssertEqual(try plan(Font.body.bold()).weight, 600)            // not 700
        XCTAssertEqual(try plan(Font.body.weight(.bold)).weight, 700)     // .weight(.bold) is bold for every style
        XCTAssertEqual(try plan(Font.headline.bold()).weight, 900)        // heavy: static Segoe UI Black
        XCTAssertEqual(try plan(Font.headline.bold()).family, "Segoe UI")
        XCTAssertEqual(try plan(Font.title.bold()).weight, 700)
        // a weight set after bold() wins; bold() after a weight wins
        XCTAssertEqual(try plan(Font.body.bold().weight(.light)).weight, 300)
        XCTAssertEqual(try plan(Font.body.weight(.light).bold()).weight, 600)
        // bold() on a sized system font is .bold
        XCTAssertEqual(try plan(Font.system(size: 13).bold()).weight, 700)
    }

    // MARK: Font.system at 9...40

    func testSystemSizesTakeTheirLineFromTheTableNotFromTheFaceRule() throws {
        for size in stride(from: 9.0, through: 40.0, by: 0.5) {
            for scale in [Float(1), 2.5] {
                let row = try XCTUnwrap(table.system(size: size, scale: Double(scale)), "\(size)")
                let p = try plan(Font.system(size: CGFloat(size)), scale: scale)
                XCTAssertEqual(Double(p.lineHeightDIP), row.height, accuracy: 1e-5, "\(size)@\(scale)")
                XCTAssertEqual(Double(p.firstBaselineDIP), row.firstBaseline, accuracy: 1e-5, "\(size)@\(scale)")
                XCTAssertEqual(Double(p.sizeDIP), size)
            }
        }
        // the old round(ascent)+round(descent) rule failed at these sizes (G26): the Mac says 13 at 10 pt (the rule said 12), 14 at 11 (13), 19 at 15 (18)
        XCTAssertEqual(try plan(Font.system(size: 10), scale: 1).lineHeightDIP, 13)
        XCTAssertEqual(try plan(Font.system(size: 11), scale: 1).lineHeightDIP, 14)
        XCTAssertEqual(try plan(Font.system(size: 15), scale: 1).lineHeightDIP, 19)
    }

    // MARK: multi-line pitch (G75b)

    func testTwelvePointPitchIs15DIPAndStacksToTheMacBlockHeights() throws {
        let p = try plan(Font.system(size: 12), scale: 2.5)
        XCTAssertEqual(p.lineHeightDIP, 15.2)   // the single line: 38 px
        XCTAssertEqual(p.linePitchDIP, 15)      // the table's scale-1 height: 37.5 px per line
        let pitchPX = Double(p.linePitchDIP) * 2.5
        func blockPX(_ n: Int) -> Double { (Double(n) * pitchPX + 0.5).rounded(.down) }   // rounded once per block, half up
        XCTAssertEqual(blockPX(1), 38); XCTAssertEqual(blockPX(2), 75); XCTAssertEqual(blockPX(3), 113)
        // centred in a 60 pt (150 px) frame: tops 37.5 px and 18.5 px before snap (Mac textTop 435.0 and 487.4 pt in frames at 420 and 480)
        XCTAssertEqual((150 - blockPX(2)) / 2, 37.5); XCTAssertEqual((150 - blockPX(3)) / 2, 18.5)
        XCTAssertEqual(blockPX(2) / 2.5, 30.0); XCTAssertEqual(blockPX(3) / 2.5, 45.2, accuracy: 1e-9)
    }

    func testShapingRequestCarriesThePitchAsLineHeight() throws {
        let req = TextMeasureRequest(text: "a b", fontID: "f", proposedWidth: 44, scale: 2.5, fontMetadata: Font.system(size: 12).metadata, lineLimit: 2)
        let m = try TextRequestAdapter.shapingRequest(for: req, body: BodyFontProfile(family: "Segoe UI", fontSizeDIP: 12, lineHeightDIP: 16), fonts: nil, scale: 2.5, textColor: 0)
        XCTAssertEqual(m.lineHeight, 15)
    }

    func testPitchRoundsHalfUpToTheMeasuredSingleLineAtEverySystemSize() throws {
        // where the scale-1 height reproduces the 2.5 single line the pitch is that height; elsewhere the single-line height stays
        for size in stride(from: 9.0, through: 40.0, by: 0.5) {
            let p = try plan(Font.system(size: CGFloat(size)), scale: 2.5)
            let h1 = try XCTUnwrap(table.system(size: size, scale: 1)).height
            XCTAssertEqual(Double(p.linePitchDIP), h1, "\(size)")
            XCTAssertEqual((Double(p.linePitchDIP) * 2.5 + 0.5).rounded(.down), Double(p.lineHeightDIP) * 2.5, accuracy: 1e-4, "\(size)")
            XCTAssertEqual(try plan(Font.system(size: CGFloat(size)), scale: 1).linePitchDIP, p.linePitchDIP.rounded(), "\(size)")
        }
    }

    func testNineWeightsMapToExistingInstancesAndEveryAdaptationIsReported() throws {
        // Segoe UI Variable instances on this build: Light 300, Regular 400, Semibold 600, Bold 700; Black 900 only in static Segoe UI (G11)
        let expected: [(Font.Weight, UInt32, String, Bool)] = [(.ultraLight, 300, "Segoe UI Variable Text", true), (.thin, 300, "Segoe UI Variable Text", true),
            (.light, 300, "Segoe UI Variable Text", false), (.regular, 400, "Segoe UI Variable Text", false), (.medium, 600, "Segoe UI Variable Text", true),
            (.semibold, 600, "Segoe UI Variable Text", false), (.bold, 700, "Segoe UI Variable Text", false), (.heavy, 900, "Segoe UI", true), (.black, 900, "Segoe UI", true)]
        for (w, weight, family, adapted) in expected {
            let p = try plan(Font.system(size: 14, weight: w))
            XCTAssertEqual(p.weight, weight, "\(w)"); XCTAssertEqual(p.family, family, "\(w)")
            let weightEntries = p.adaptations.filter { $0.kind == .weight }
            XCTAssertEqual(!weightEntries.isEmpty, adapted, "\(w)")
            if let e = weightEntries.first {
                XCTAssertTrue(e.requested.hasPrefix("\(w.rawValue)("), e.requested)
                XCTAssertTrue(e.applied.hasSuffix("\(weight)"), e.applied)
                XCTAssertTrue(e.description.hasPrefix("FONT_ADAPTED kind=weight "), e.description)
                XCTAssertFalse(e.reason.isEmpty)
            }
        }
    }

    func testRepresentativeGridOfSizesAndWeightsAlwaysResolves() throws {
        // 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32 pt x nine weights x scale 1 and 2.5 (the F2 case grid)
        for size in [9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32] {
            for w in weights {
                for scale in [Float(1), 2.5] {
                    let p = try plan(Font.system(size: CGFloat(size), weight: w), scale: scale)
                    XCTAssertTrue([300, 400, 600, 700, 900].contains(p.weight), "\(size) \(w) -> \(p.weight)")
                    XCTAssertEqual(p.simulations, .forbidAll)
                    XCTAssertTrue(p.features.contains(.kern))
                }
            }
        }
    }

    func testOpticalFamilyByNearestOpszInLogDistance() {
        XCTAssertEqual(SegoeOpticalFamily.smallTextBoundaryDIP, 12.2, accuracy: 0.05)
        XCTAssertEqual(SegoeOpticalFamily.textDisplayBoundaryDIP, 25.9, accuracy: 0.05)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 9), .small)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 12), .small)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 12.5), .text)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 13), .text)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 25.5), .text)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 26), .display)
        XCTAssertEqual(SegoeOpticalFamily.family(forSizeDIP: 40), .display)
    }

    // MARK: designs

    func testMonospacedIsCascadiaMonoWithTheMacMonospacedLine() throws {
        let p = try plan(Font.system(size: 13, weight: .regular, design: .monospaced), scale: 1)
        XCTAssertEqual(p.family, "Cascadia Mono"); XCTAssertEqual(p.weight, 400); XCTAssertEqual(p.fallbackFamilies, ["Consolas"])
        XCTAssertEqual(Double(p.lineHeightDIP), table.system(size: 13, design: "monospaced", scale: 1)?.height)
        XCTAssertEqual(try plan(Font.system(size: 13, weight: .thin, design: .monospaced)).weight, 200)
        XCTAssertEqual(try plan(Font.system(size: 13, weight: .heavy, design: .monospaced)).weight, 700)
        XCTAssertTrue(try plan(Font.system(size: 13, weight: .heavy, design: .monospaced)).adaptations.contains { $0.kind == .weight })
        // Consolas where Cascadia is absent
        let noCascadia = SystemFontAvailability(cascadiaMono: false)
        let c = try plan(Font.system(size: 13, weight: .semibold, design: .monospaced), availability: noCascadia)
        XCTAssertEqual(c.family, "Consolas"); XCTAssertEqual(c.weight, 700)
        XCTAssertTrue(c.adaptations.contains { $0.kind == .family })
    }

    func testSerifIsSitkaWithTheMacSerifLine() throws {
        // New York at 13 pt is 16 tall with baseline 12 (G22); the default is baseline 13
        let p = try plan(Font.system(size: 13, weight: .regular, design: .serif), scale: 1)
        XCTAssertEqual(p.family, "Sitka Text"); XCTAssertEqual(p.lineHeightDIP, 16); XCTAssertEqual(p.firstBaselineDIP, 12)
        XCTAssertEqual(try plan(Font.system(size: 13), scale: 1).firstBaselineDIP, 13)
        XCTAssertEqual(try plan(Font.system(size: 40, design: .serif), scale: 1).lineHeightDIP, 48)
        XCTAssertEqual(try plan(Font.system(size: 14, weight: .semibold, design: .serif)).weight, 700)
        XCTAssertTrue(try plan(Font.system(size: 14, weight: .semibold, design: .serif)).adaptations.contains { $0.kind == .weight })
        let g = try plan(Font.system(size: 14, design: .serif), availability: SystemFontAvailability(sitka: false))
        XCTAssertEqual(g.family, "Georgia")
    }

    func testRoundedIsTheDefaultDesignReportedAsAdapted() throws {
        let p = try plan(Font.system(size: 15, weight: .medium, design: .rounded))
        XCTAssertEqual(p.family, "Segoe UI Variable Text")
        let d = try XCTUnwrap(p.adaptations.first { $0.kind == .design })
        XCTAssertEqual(d.requested, "rounded")
        XCTAssertTrue(d.applied.hasPrefix("default"))
        // the Mac rounded design has the default heights (G22)
        XCTAssertEqual(p.lineHeightDIP, try plan(Font.system(size: 15, weight: .medium)).lineHeightDIP)
        XCTAssertTrue(try plan(Font.system(size: 15, design: .default)).adaptations.filter { $0.kind == .design }.isEmpty)
    }

    func testStyleWithADesignUsesThatDesignsRow() throws {
        let md = Font.Metadata(design: .serif, textStyle: "title")
        let p = try mapper.plan(for: md, scale: 1)
        XCTAssertEqual(p.family, "Sitka Text")
        XCTAssertEqual(Double(p.lineHeightDIP), table.style("title", variant: "design-serif", scale: 1)?.height)
    }

    func testWithoutSegoeVariableTheStaticFamilyAndItsWeightsApply() throws {
        let a = SystemFontAvailability(segoeUIVariable: false)
        let thin = try plan(Font.system(size: 13, weight: .thin), availability: a)
        XCTAssertEqual(thin.family, "Segoe UI"); XCTAssertEqual(thin.weight, 300)
        XCTAssertTrue(thin.adaptations.contains { $0.kind == .family })
        XCTAssertTrue(thin.adaptations.contains { $0.kind == .weight })
        XCTAssertEqual(try plan(Font.system(size: 13, weight: .black), availability: a).weight, 900)
        XCTAssertFalse(try plan(Font.system(size: 13, weight: .black), availability: a).adaptations.contains { $0.kind == .weight })
        XCTAssertEqual(try plan(Font.system(size: 13, weight: .medium), availability: a).weight, 600)
        // line geometry does not depend on the Windows face
        XCTAssertEqual(try plan(Font.system(size: 13), availability: a).lineHeightDIP, try plan(Font.system(size: 13)).lineHeightDIP)
    }

    // MARK: width, features

    func testWidthIsStandardAndNonStandardIsReportedAdapted() throws {
        XCTAssertTrue(try plan(Font.system(size: 14)).adaptations.filter { $0.kind == .width }.isEmpty)
        XCTAssertTrue(try plan(Font.system(size: 14).width(.standard)).adaptations.filter { $0.kind == .width }.isEmpty)
        for w in [Font.Width.condensed, .compressed, .expanded] {
            let e = try XCTUnwrap(try plan(Font.system(size: 14).width(w)).adaptations.first { $0.kind == .width })
            XCTAssertEqual(e.requested, w.name); XCTAssertEqual(e.applied, "standard")
        }
        // the frame does not change with the width (the Mac table has no width rows; G29a)
        XCTAssertEqual(try plan(Font.system(size: 14).width(.expanded)).lineHeightDIP, try plan(Font.system(size: 14)).lineHeightDIP)
    }

    func testKerningIsOnEveryRunAndMonospacedDigitAddsTnum() throws {
        XCTAssertEqual(try plan(Font.body).features, [.kern])
        XCTAssertEqual(try plan(Font.body.monospacedDigit()).features, [.kern, .tabularNumbers])
        XCTAssertEqual(try plan(Font.system(size: 20, weight: .semibold).monospacedDigit()).features.map { $0.tagString }, ["kern", "tnum"])
        XCTAssertEqual(try plan(Font.body).textExtension, TextExtension(features: [.kern], simulations: .forbidAll, fallbackFamilies: ["Segoe UI"], baselineOffsetDIP: 13.2))
        // the monospacedDigit frame is the base font's (not measured separately: G29a)
        XCTAssertEqual(try plan(Font.body.monospacedDigit()).lineHeightDIP, try plan(Font.body).lineHeightDIP)
    }

    func testAbi07LimitsAreReportedNotSilent() throws {
        let limits = SystemFontMapper.abi07Limits(of: try plan(Font.body))
        XCTAssertEqual(limits.map { $0.requested }, ["kern=1", "first baseline from the Mac table"])
        XCTAssertTrue(limits.allSatisfy { $0.reason.contains("0.8") })
        let digits = SystemFontMapper.abi07Limits(of: try plan(Font.body.monospacedDigit()))
        XCTAssertTrue(digits.contains { $0.requested.contains("tnum") })
    }

    func testAdaptationLogReportsEachEntryOnce() throws {
        var log = FontAdaptationLog()
        let a = try plan(Font.system(size: 14, weight: .ultraLight)).adaptations
        XCTAssertEqual(log.record(a).count, a.count)
        XCTAssertEqual(log.record(a), [])
        let b = try plan(Font.system(size: 14, weight: .thin)).adaptations
        XCTAssertEqual(log.record(b).count, 1)    // thin -> Light is a different entry from ultraLight -> Light
        XCTAssertEqual(log.entries.count, a.count + 1)
    }

    // MARK: refusals

    func testOtherScalesAndUnmeasuredSizesFailVisibly() {
        XCTAssertThrowsError(try plan(Font.body, scale: 2)) { XCTAssertEqual($0 as? TextMeasureError, .unsupportedScale(2)) }
        XCTAssertThrowsError(try plan(Font.body, scale: 1.5)) { XCTAssertEqual($0 as? TextMeasureError, .unsupportedScale(1.5)) }
        XCTAssertThrowsError(try plan(Font.system(size: 8.5))) { XCTAssertTrue(String(describing: $0).contains("systemFontMetricsUnavailable")) }
        XCTAssertThrowsError(try plan(Font.system(size: 41)))
        XCTAssertThrowsError(try plan(Font.system(size: 13.25)))      // not a half point
        XCTAssertThrowsError(try plan(Font.system(size: 0))) { XCTAssertEqual($0 as? TextMeasureError, .invalidPointSize) }
        XCTAssertThrowsError(try plan(Font.system(size: 513))) { XCTAssertEqual($0 as? TextMeasureError, .invalidPointSize) }
        XCTAssertThrowsError(try mapper.plan(for: Font.Metadata(textStyle: "huge"), scale: 1))
    }

    // MARK: the hub theme fonts (F15)

    func testHubThemeFonts() throws {
        // pageTitle 22 semibold, title 15 bold, lead 13.5, body 13, label 12.5 semibold, caption 12, small 11.5, micro 11 semibold, stat 22 semibold
        let theme: [(String, Font, String, UInt32, Double)] = [
            ("pageTitle", .system(size: 22, weight: .semibold), "Segoe UI Variable Text", 600, 26),
            ("title", .system(size: 15, weight: .bold), "Segoe UI Variable Text", 700, 19),
            ("lead", .system(size: 13.5), "Segoe UI Variable Text", 400, 16),
            ("body", .system(size: 13), "Segoe UI Variable Text", 400, 16),
            ("label", .system(size: 12.5, weight: .semibold), "Segoe UI Variable Text", 600, 15),
            ("caption", .system(size: 12), "Segoe UI Variable Small", 400, 15),
            ("small", .system(size: 11.5), "Segoe UI Variable Small", 400, 14),
            ("micro", .system(size: 11, weight: .semibold), "Segoe UI Variable Small", 600, 14),
            ("stat", .system(size: 22, weight: .semibold), "Segoe UI Variable Text", 600, 26),
        ]
        for (name, font, family, weight, height) in theme {
            let p = try plan(font, scale: 1)
            XCTAssertEqual(p.family, family, name); XCTAssertEqual(p.weight, weight, name)
            XCTAssertEqual(Double(p.lineHeightDIP), table.system(size: Double(font.metadata!.pointSize!), scale: 1)?.height, name)
            XCTAssertEqual(Double(p.lineHeightDIP), height, name)
            XCTAssertTrue(p.adaptations.isEmpty, "\(name): \(p.adaptations)")   // nothing in the hub theme is adapted
        }
    }
}

private extension Font {
    /// The static text-style font by name.
    init(styleNamed name: String) {
        switch name {
        case "largeTitle": self = .largeTitle
        case "title": self = .title
        case "title2": self = .title2
        case "title3": self = .title3
        case "headline": self = .headline
        case "subheadline": self = .subheadline
        case "body": self = .body
        case "callout": self = .callout
        case "footnote": self = .footnote
        case "caption": self = .caption
        default: self = .caption2
        }
    }
}
