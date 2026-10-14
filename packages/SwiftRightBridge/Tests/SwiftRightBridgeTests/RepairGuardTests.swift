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
        let s = RepairGuard.scriptFile
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: RepairGuardScript.source, configJSON: cfg, pfn: "A_b"), "the old newline-less deployed copy is replaced")
        XCTAssertFalse(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: nil, configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s + " ", configJSON: cfg, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: nil, pfn: "A_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: cfg, pfn: "Other_b"))
        XCTAssertTrue(RepairGuard.needsInstall(scriptOnDisk: s, configJSON: Data("{}".utf8), pfn: "A_b"))
    }

    func testTaskMissingTriggersInstall() {
        let cfg = Data(#"{"pfn":"A_b","task":"A_b-Repair"}"#.utf8)
        let s = RepairGuard.scriptFile
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

    func testDeployedFileIsByteIdenticalToPinnedFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("guard/msix-repair-guard.ps1")
        let pinned = try Data(contentsOf: file)
        XCTAssertEqual(Data(RepairGuard.scriptFile.utf8), pinned.filter { $0 != 13 }, "writer output keeps the final newline")
        XCTAssertEqual(RepairGuard.scriptFile.utf8.last, 10)
    }

    func testMarkerWrittenOnlyAfterSpawn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rg-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("install-attempt.json")
        let failure = dir.appendingPathComponent("install-launch-failure.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // spawn failure: failure recorded, no marker, so the next launch is not blocked
        XCTAssertEqual(RepairGuard.recordLaunch(dir: dir, spawned: false, failure: "CreateProcessW failed, error 2", now: now), failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: failure)) as? [String: Any])
        XCTAssertEqual(object["launchFailure"] as? String, "CreateProcessW failed, error 2")
        XCTAssertFalse(RepairGuard.installAttemptBlocked(markerJSON: try? Data(contentsOf: marker), now: now.addingTimeInterval(60)))
        // spawned: marker written, failure record cleared
        XCTAssertEqual(RepairGuard.recordLaunch(dir: dir, spawned: true, failure: nil, now: now), marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failure.path))
        XCTAssertTrue(RepairGuard.installAttemptBlocked(markerJSON: try? Data(contentsOf: marker), now: now.addingTimeInterval(60)))
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
