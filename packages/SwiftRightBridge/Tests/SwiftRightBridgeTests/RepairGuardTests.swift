import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import SwiftRightBridge

final class RepairGuardTests: XCTestCase {
    func testEmbeddedScriptMatchesSourceFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("guard/msix-repair-guard.ps1")
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

    func testTaskMissingTriggersInstall() {
        let cfg = Data(#"{"pfn":"A_b","task":"A_b-Repair"}"#.utf8)
        let s = RepairGuardScript.source
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "A_b", taskExists: { false }))
        XCTAssertFalse(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "A_b", taskExists: { true }))
        // the task probe only runs when the cheap file checks pass
        var probed = false
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: nil, configJSON: cfg, pfn: "A_b", taskExists: { probed = true; return true }))
        XCTAssertFalse(probed)
    }

    func testAttemptBackoffMarker() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sha = RepairGuardScript.sha256
        let marker = RepairGuard.attemptMarker(now: now.addingTimeInterval(-3600))
        XCTAssertTrue(RepairGuard.installAttemptBlocked(markerJSON: marker, now: now))
        XCTAssertFalse(RepairGuard.installAttemptBlocked(markerJSON: nil, now: now))
        XCTAssertFalse(RepairGuard.installAttemptBlocked(markerJSON: Data("junk".utf8), now: now))
        XCTAssertFalse(RepairGuard.installAttemptBlocked(markerJSON: RepairGuard.attemptMarker(now: now.addingTimeInterval(-24 * 3600 - 1)), now: now), "retried after 24 h")
        XCTAssertFalse(RepairGuard.installAttemptBlocked(markerJSON: RepairGuard.attemptMarker(now: now.addingTimeInterval(-60), scriptSha256: "0" + sha.dropFirst()), now: now), "a changed script is retried at once")
    }

    #if canImport(CryptoKit)
    func testEmbeddedScriptIsThePinnedRightKitCanonicalFile() throws {
        let guardDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("guard")
        let pin = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: guardDir.appendingPathComponent("rightkit-pin.json"))) as? [String: Any])
        let embedded = SHA256.hash(data: Data(RepairGuardScript.source.utf8) + Data("\n".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(embedded, RepairGuardScript.sha256)
        XCTAssertEqual(pin["sha256"] as? String, embedded, "guard/rightkit-pin.json must carry the sha256 RightKit's msixRepairGuard() returns for the pinned commit")
        XCTAssertEqual(pin["canonical"] as? String, "rightkit/packages/release/msix-repair-guard.ps1")
        let commit = try XCTUnwrap(pin["rightkitCommit"] as? String)
        XCTAssertNotNil(commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression), "pin names a RightKit commit")
        XCTAssertNotNil(pin["rightkitPackageVersion"] as? String)
        // the RightKit checkout, when present beside this repository, must agree byte for byte
        let rightkit = URL(fileURLWithPath: "/Volumes/D/claude/rightkit/packages/release/msix-repair-guard.ps1")
        if let canonical = try? String(contentsOf: rightkit, encoding: .utf8) {
            XCTAssertEqual(canonical.replacingOccurrences(of: "\r\n", with: "\n"), RepairGuardScript.source + "\n", "RightKit canonical file changed: --sync and re-pin")
        }
    }
    #endif

    func testScriptSafetyContract() {
        let s = RepairGuardScript.source
        for needle in ["Test-AllowedUri", "Test-Identity", "last-result.json", "retry.json", "<TimeTrigger>", "install-attempt.json"] { XCTAssertTrue(s.contains(needle), needle) }
        XCTAssertFalse(s.unicodeScalars.contains { $0.value > 127 }, "ASCII only (Windows PowerShell 5.1)")
    }

    func testSanitizedName() {
        XCTAssertEqual(RepairGuard.sanitized("Slice/App: 1"), "Slice_App_ 1")
        XCTAssertEqual(RepairGuard.sanitized("..."), "App")
    }
}
