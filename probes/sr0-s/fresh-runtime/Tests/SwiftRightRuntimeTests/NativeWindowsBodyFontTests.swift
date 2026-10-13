import SwiftRightRuntime
import XCTest

final class NativeWindowsBodyFontTests: XCTestCase {
    func testRejectsOutOfRangeDPIBeforePlatformResolution() {
        XCTAssertThrowsError(try NativeWindowsBodyFontResolver.resolve(dpi: 0, emitLog: false)) { error in
            XCTAssertEqual(error as? NativeWindowsBodyFontError, .invalidDPI)
        }
    }

    func testPublicPolicyValuePreservesMeasuredUnitsAndIdentity() {
        let policy = NativeWindowsBodyFont(
            family: "profile-family", fontSizeDIP: 16, lineHeightDIP: 24,
            weight: 400, logFontHeight: -16, textMetricHeight: 24,
            textMetricAscent: 18, textMetricDescent: 5,
            textMetricExternalLeading: 1, dpi: 96,
            sourceAPI: "test-profile")
        XCTAssertEqual(policy.family, "profile-family")
        XCTAssertEqual(policy.fontSizeDIP, 16)
        XCTAssertEqual(policy.lineHeightDIP, 24)
        XCTAssertEqual(policy.dpi, 96)
        XCTAssertEqual(policy.sourceAPI, "test-profile")
    }

    func testCoreTextLineHeightIsRoundedAscentPlusRoundedDescent() {
        func policy(_ upm: UInt16?, _ a: Int16?, _ d: Int16?, size: Float) -> NativeWindowsBodyFont {
            NativeWindowsBodyFont(family: "Segoe UI", fontSizeDIP: size, lineHeightDIP: 16.4, weight: 400, logFontHeight: -30, textMetricHeight: 41,
                                  textMetricAscent: 33, textMetricDescent: 8, textMetricExternalLeading: 0, dpi: 240, sourceAPI: "t",
                                  unitsPerEm: upm, hheaAscentUnits: a, hheaDescentUnits: d)
        }
        // Segoe UI 12 DIP: hhea 2210 / -514 over 2048 -> 12.95 / 3.01 -> 13 + 3 = 16 (GDI tmHeight says 16.4).
        XCTAssertEqual(policy(2048, 2210, -514, size: 12).coreTextLineHeightDIP, 16)
        XCTAssertEqual(policy(2048, 2210, -514, size: 9).coreTextLineHeightDIP, 12)    // 9.71 -> 10, 2.26 -> 2
        XCTAssertNil(policy(nil, nil, nil, size: 12).coreTextLineHeightDIP)
        XCTAssertNil(policy(0, 2210, -514, size: 12).coreTextLineHeightDIP)
    }

#if os(Windows)
    func testLiveProfileCarriesTheResolvedFacesHheaMetrics() throws {
        let policy = try NativeWindowsBodyFontResolver.resolve(dpi: 240, emitLog: false)
        let upm = try XCTUnwrap(policy.unitsPerEm), asc = try XCTUnwrap(policy.hheaAscentUnits), desc = try XCTUnwrap(policy.hheaDescentUnits)
        XCTAssertGreaterThan(upm, 0); XCTAssertGreaterThan(asc, 0); XCTAssertLessThan(desc, 0)
        let line = try XCTUnwrap(policy.coreTextLineHeightDIP)
        XCTAssertGreaterThan(line, policy.fontSizeDIP)
        XCTAssertLessThan(abs(line - policy.lineHeightDIP), 2)
    }

    func testResolvesLiveDPI96ProfileWithConsistentUnits() throws {
        let policy = try NativeWindowsBodyFontResolver.resolve(dpi: 96, emitLog: false)
        assertLiveUnits(policy, dpi: 96)
    }

    func testResolvesLiveDPI240ProfileWithConsistentUnits() throws {
        let policy = try NativeWindowsBodyFontResolver.resolve(dpi: 240, emitLog: false)
        assertLiveUnits(policy, dpi: 240)
    }

    private func assertLiveUnits(_ policy: NativeWindowsBodyFont, dpi: UInt32) {
        let scale = Double(dpi) / 96
        XCTAssertEqual(policy.dpi, dpi)
        XCTAssertFalse(policy.family.isEmpty)
        XCTAssertGreaterThan(policy.fontSizeDIP, 0)
        XCTAssertGreaterThan(policy.lineHeightDIP, 0)
        XCTAssertGreaterThan(policy.textMetricHeight, 0)
        XCTAssertGreaterThanOrEqual(policy.textMetricAscent, 0)
        XCTAssertGreaterThanOrEqual(policy.textMetricDescent, 0)
        XCTAssertTrue(policy.sourceAPI.contains("SystemParametersInfoForDpi"))
        // LOGFONT & TEXTMETRIC values are physical pixels at requested DPI;
        // public runtime fields remain DIPs, so convert with dpi/96 scale.
        XCTAssertEqual(Double(policy.fontSizeDIP) * scale,
                       Double(abs(policy.logFontHeight)), accuracy: 0.01)
        XCTAssertEqual(Double(policy.lineHeightDIP) * scale,
                       Double(policy.textMetricHeight), accuracy: 0.01)
    }
#endif
}
