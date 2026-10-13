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

#if os(Windows)
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
