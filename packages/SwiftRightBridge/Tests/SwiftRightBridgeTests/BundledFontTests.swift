import CSwiftRight
import Foundation
import XCTest
@testable import SwiftRightBridge

// Fake renderer entry points: plain C-convention functions, no DLL, so the 0.6/0.7 negotiation and the
// font marshalling run on every host.

private nonisolated(unsafe) var fakeRegistered: [[UInt8]] = []
private nonisolated(unsafe) var fakeSeenStructSize: UInt32 = 0

private let fakeRegister: FontRegisterFn = { bytes, len, out in
    guard let bytes, let out else { return -1 }
    fakeSeenStructSize = out.pointee.struct_size
    if out.pointee.struct_size < UInt32(MemoryLayout<swr_font_info>.size) { return -14 }
    let data = Array(UnsafeBufferPointer(start: bytes, count: Int(len)))
    if data.first == 0xFF { return -1 }              // "not a font"
    let dup = fakeRegistered.contains(data)
    if !dup { fakeRegistered.append(data) }
    out.pointee.flags = dup ? UInt32(SWR_FONT_DUPLICATE) : UInt32(SWR_FONT_NEW)
    out.pointee.font = (1 << 32) | UInt64(fakeRegistered.firstIndex(of: data)! + 1)
    out.pointee.weight = 400
    out.pointee.face_count = 1
    let name = Array("Tinos".utf8)
    out.pointee.family_len = UInt32(name.count)
    withUnsafeMutableBytes(of: &out.pointee.family) { raw in
        for (i, b) in name.enumerated() { raw[i] = b }
    }
    withUnsafeMutableBytes(of: &out.pointee.sha256) { raw in for i in 0..<32 { raw[i] = UInt8(i) } }
    return 0
}

private let fakeResolve: FontResolveFn = { family, len, out in
    guard let family, let out else { return -1 }
    let name = String(decoding: UnsafeBufferPointer(start: family, count: Int(len)), as: UTF8.self)
    let known = !fakeRegistered.isEmpty && name.lowercased() == "tinos"
    out.pointee.source = known ? UInt32(SWR_FONT_SRC_BUNDLED) : UInt32(SWR_FONT_SRC_FALLBACK)
    out.pointee.font = known ? (1 << 32) | 1 : 0
    return 0
}

final class BundledFontTests: XCTestCase {
    override func setUp() { fakeRegistered = []; fakeSeenStructSize = 0 }

    private func v07Info() -> swr_bootstrap_info_v07 {
        var i = swr_bootstrap_info_v07()
        i.struct_size = UInt32(MemoryLayout<swr_bootstrap_info_v07>.size)
        i.abi_major = UInt32(SWR_ABI_MAJOR)
        i.abi_minor = UInt32(SWR_ABI_MINOR_V07)
        i.pointer_width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        withUnsafeMutableBytes(of: &i.arch) { raw in for (n, b) in "x86_64".utf8.enumerated() { raw[n] = b } }
        i.host_callbacks_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        i.api_table_size = UInt32(MemoryLayout<swr_api_v07>.size)
        i.transaction_size = UInt32(MemoryLayout<swr_transaction>.size)
        i.node_size = UInt32(MemoryLayout<swr_node>.size)
        i.primitive_size = UInt32(MemoryLayout<swr_primitive>.size)
        i.semantic_size = UInt32(MemoryLayout<swr_semantic>.size)
        i.ax_text_run_size = UInt32(MemoryLayout<swr_ax_text_run>.size)
        i.event_size = UInt32(MemoryLayout<swr_event>.size)
        i.measure_request_size = UInt32(MemoryLayout<swr_measure_request>.size)
        i.measure_result_size = UInt32(MemoryLayout<swr_measure_result>.size)
        i.line_info_size = UInt32(MemoryLayout<swr_line_info>.size)
        i.char_cell_size = UInt32(MemoryLayout<swr_char_cell>.size)
        i.fn_count = UInt32(SWR_API_V07_FN_COUNT)
        i.stats_size = UInt32(MemoryLayout<swr_stats>.size)
        i.font_info_size = UInt32(MemoryLayout<swr_font_info>.size)
        i.font_resolution_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        return i
    }

    private func v06Info() -> swr_bootstrap_info {
        var b = NegotiationFixtures.base(from: v07Info())
        b.abi_minor = UInt32(SWR_ABI_MINOR)
        b.api_table_size = UInt32(MemoryLayout<swr_api>.size)
        b.fn_count = UInt32(SWR_API_FN_COUNT)
        return b
    }

    // MARK: layouts the header promises

    func testLayoutsMatchTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info>.size, 88, "0.6 bootstrap unchanged")
        XCTAssertEqual(MemoryLayout<swr_api>.size, 136, "0.6 table unchanged")
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v07>.size, 96)
        XCTAssertEqual(MemoryLayout<swr_api_v07>.size, 152)
        XCTAssertEqual(MemoryLayout<swr_api_v07>.offset(of: \.font_register), 136)
        XCTAssertEqual(MemoryLayout<swr_api_v07>.offset(of: \.image_release), 128, "0.6 prefix keeps its offsets")
        XCTAssertEqual(MemoryLayout<swr_font_info>.size, 128)
        XCTAssertEqual(MemoryLayout<swr_font_resolution>.size, 48)
        XCTAssertEqual(SWR_ABI_MINOR, 6, "the legacy constant must not move")
        XCTAssertEqual(SWR_API_FN_COUNT, 16)
    }

    // MARK: negotiation

    func testBothExportsSelect07() throws {
        XCTAssertEqual(try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, minimum: .v06), .v07)
        XCTAssertEqual(try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, minimum: .v07), .v07)
    }

    func testBridge07OnA06RendererFallsBackOrRefuses() throws {
        // New bridge, old (0.6) renderer: no versioned exports.
        XCTAssertEqual(try BridgeNegotiation.choose(hasBootstrapV07: false, hasApiV07: false, minimum: .v06), .v06)
        XCTAssertThrowsError(try BridgeNegotiation.choose(hasBootstrapV07: false, hasApiV07: false, minimum: .v07)) {
            XCTAssertTrue(String(describing: $0).contains("SWR_STARTUP_ERROR"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.6"))
        }
    }

    func testHalfExportedRendererIsRefused() {
        XCTAssertThrowsError(try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: false, minimum: .v06))
        XCTAssertThrowsError(try BridgeNegotiation.choose(hasBootstrapV07: false, hasApiV07: true, minimum: .v06))
    }

    func testLegacyViewOfA07RendererIsStillA06View() throws {
        // Old bridge, new renderer: the legacy bootstrap reports minor 6 / 136 bytes / 16 functions and
        // the unchanged 0.6 validation accepts it.
        try Bridge.validate(v06Info())
        // ...and rejects a legacy view that claims 0.7 (the 0.7 numbers belong to the _v07 view only).
        var wrong = v06Info()
        wrong.abi_minor = UInt32(SWR_ABI_MINOR_V07)
        XCTAssertThrowsError(try Bridge.validate(wrong))
    }

    func testValidate07AcceptsTheTrueViewAndRejectsEveryDrift() throws {
        try BridgeNegotiation.validateV07(v07Info())
        var a = v07Info(); a.abi_minor = 6
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(a), "a 0.6 minor is not a 0.7 view")
        var b = v07Info(); b.api_table_size = 136
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(b), "the 0.7 table is 152 bytes")
        var c = v07Info(); c.fn_count = 16
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(c))
        var d = v07Info(); d.font_info_size = 96
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(d))
        var e = v07Info(); e.font_resolution_size = 0
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(e))
        var f = v07Info(); f.node_size += 8
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(f))
        var g = v07Info(); g.pointer_width = 32
        XCTAssertThrowsError(try BridgeNegotiation.validateV07(g))
    }

    func testBaseViewKeepsTheRenderersOwnNumbers() {
        let b = BridgeNegotiation.baseView(of: v07Info())
        XCTAssertEqual(b.abi_minor, 7)
        XCTAssertEqual(b.api_table_size, 152)
        XCTAssertEqual(b.fn_count, 18)
        XCTAssertEqual(b.stats_size, UInt32(MemoryLayout<swr_stats>.size))
    }

    // MARK: font marshalling and fallback reporting

    private func bridge07() -> Bridge {
        Bridge(api: swr_api(), info: BridgeNegotiation.baseView(of: v07Info()), revision: .v07,
               fonts: FontEntryPoints(register: fakeRegister, resolve: fakeResolve))
    }

    private func bridge06() -> Bridge {
        Bridge(api: swr_api(), info: v06Info(), revision: .v06, fonts: nil)
    }

    func testRegisterFontOn07ReturnsIdentity() throws {
        let b = bridge07()
        XCTAssertTrue(b.supportsFontRegistration)
        let reg = try b.registerFont([1, 2, 3, 4])
        XCTAssertEqual(fakeSeenStructSize, 128, "the bridge sets struct_size before the call")
        XCTAssertEqual(reg.family, "Tinos")
        XCTAssertEqual(reg.weight, 400)
        XCTAssertEqual(reg.faceCount, 1)
        XCTAssertEqual(reg.sha256.count, 32)
        XCTAssertTrue(reg.flags.contains(.new))
        XCTAssertNotEqual(reg.handle, 0)
        let again = try b.registerFont([1, 2, 3, 4])
        XCTAssertTrue(again.flags.contains(.duplicate))
        XCTAssertEqual(again.handle, reg.handle)
    }

    func testRegisterFontPropagatesRendererRefusal() {
        XCTAssertThrowsError(try bridge07().registerFont([0xFF, 0, 0])) {
            guard case BridgeError.status(let rc, _) = $0 else { return XCTFail("\($0)") }
            XCTAssertEqual(rc, -1)
        }
        XCTAssertThrowsError(try bridge07().registerFont([]))
    }

    func testA06RendererReportsFontsUnsupportedNotSilentFallback() {
        let b = bridge06()
        XCTAssertFalse(b.supportsFontRegistration)
        XCTAssertThrowsError(try b.registerFont([1, 2, 3])) {
            guard case BridgeError.status(let rc, _) = $0 else { return XCTFail("\($0)") }
            XCTAssertEqual(rc, -15, "SWR_E_UNSUPPORTED")
        }
        XCTAssertThrowsError(try b.resolveFont(family: "Tinos"))
    }

    func testResolveReportsFallbackBeforeRegistrationAndBundledAfter() throws {
        let b = bridge07()
        XCTAssertEqual(try b.resolveFont(family: "Tinos").source, .fallback, "negative control: not registered yet")
        _ = try b.registerFont([9, 9, 9])
        let after = try b.resolveFont(family: "tinos")
        XCTAssertEqual(after.source, .bundled)
        XCTAssertNotEqual(after.handle, 0)
        XCTAssertEqual(try b.resolveFont(family: "NoSuchFamily").source, .fallback, "an unregistered family never reports bundled")
    }

    // MARK: bundled font library (Font.custom name -> provider family)

    func testLibraryRegistersResourceDirectoryAndMapsCustomNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swr-fonts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Fonts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([7, 7, 7]).write(to: dir.appendingPathComponent("Fonts/Tinos-Regular.ttf"))
        try Data([1]).write(to: dir.appendingPathComponent("readme.txt"))
        let lib = BundledFontLibrary(bridge: bridge07())
        let regs = try lib.registerAll(in: dir)
        XCTAssertEqual(regs.count, 1, "only font files register")
        XCTAssertEqual(lib.providerFamily(forCustomName: "Tinos"), "Tinos")
        XCTAssertEqual(lib.providerFamily(forCustomName: "Tinos-Regular"), "Tinos", "PostScript-style name and file stem")
        XCTAssertNil(lib.providerFamily(forCustomName: "Georgia"), "no bundled font answers: the caller must not invent one")
    }

    func testLibraryOn06RendererThrowsWhenThereIsAFontToRegister() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swr-fonts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BundledFontLibrary(bridge: bridge06())
        XCTAssertEqual(try lib.registerAll(in: dir).count, 0, "nothing bundled: a 0.6 renderer is fine")
        try Data([7, 7, 7]).write(to: dir.appendingPathComponent("Tinos-Regular.ttf"))
        XCTAssertThrowsError(try lib.registerAll(in: dir))
    }
}

enum NegotiationFixtures {
    static func base(from v: swr_bootstrap_info_v07) -> swr_bootstrap_info { BridgeNegotiation.baseView(of: v) }
}
