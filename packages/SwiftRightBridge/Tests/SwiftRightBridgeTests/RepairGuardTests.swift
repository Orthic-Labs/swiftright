import Foundation
import XCTest
@testable import SwiftRightBridge

final class RepairGuardTests: XCTestCase {
    func testEmbeddedScriptMatchesSourceFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("guard/repair-guard.ps1")
        let text = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        XCTAssertEqual(RepairGuardScript.source + "\n", text, "run node tools/gen-repair-guard.mjs")
    }

    func testNeedsInstallDecisions() {
        let cfg = Data(#"{"pfn":"A_b","task":"A_b-Repair"}"#.utf8)
        let s = RepairGuardScript.source
        XCTAssertFalse(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: nil, configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s + " ", configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: nil, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "Other_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: Data("{}".utf8), pfn: "A_b"))
    }

    func testSanitizedName() {
        XCTAssertEqual(RepairGuard.sanitized("Slice/App: 1"), "Slice_App_ 1")
        XCTAssertEqual(RepairGuard.sanitized("..."), "App")
    }
}
