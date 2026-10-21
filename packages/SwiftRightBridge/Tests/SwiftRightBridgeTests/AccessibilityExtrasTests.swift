import XCTest
@testable import SwiftRightBridge
import CSwiftRight

// ABI 0.13 (issue #60 item 6): accessibility extras (hint, value, description, header and link traits). Layout, negotiation,
// validation, marshalling and the version gate of the transaction. The renderer side (table validation, AccessKit mapping to
// UIA HelpText, FullDescription, Value, Heading level and Hyperlink) is covered by render/swiftright-render src/tree.rs
// `ax_extras_table`, src/ax.rs `extras_tests` and src/lib.rs `bootstrap_v13_extends_v12_and_reports_minor_13`.

nonisolated(unsafe) private var seenStructSize: UInt32 = 0
nonisolated(unsafe) private var seenExtras: [(id: UInt64, help: String, value: String, description: String, flags: UInt32, level: UInt32)] = []

private func text(_ s: swr_str) -> String {
    guard let p = s.ptr, s.len > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: p, count: Int(s.len)), as: UTF8.self)
}

private func fakeCommit(_ t: UnsafePointer<swr_transaction>?) -> Int32 {
    guard let t else { return -1 }
    seenStructSize = t.pointee.struct_size
    seenExtras = []
    if Int(t.pointee.struct_size) >= MemoryLayout<swr_transaction_v13>.size {
        t.withMemoryRebound(to: swr_transaction_v13.self, capacity: 1) { p in
            if let e = p.pointee.extras {
                for x in UnsafeBufferPointer(start: e, count: Int(p.pointee.extra_count)) {
                    seenExtras.append((x.id, text(x.help), text(x.value), text(x.description), x.flags, x.heading_level))
                }
            }
        }
    }
    return 0
}

final class AccessibilityExtrasTests: XCTestCase {
    func testLayoutMatchesTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_ax_extra_entry>.size, 64)
        XCTAssertEqual(MemoryLayout<swr_ax_extra_entry>.offset(of: \.flags), 56)
        XCTAssertEqual(MemoryLayout<swr_transaction_v13>.size, 144)
        XCTAssertEqual(MemoryLayout<swr_transaction_v13>.offset(of: \.extras), 128)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v13>.size, 160)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v13>.offset(of: \.ax_extra_entry_size), 152)
        XCTAssertEqual(SWR_ABI_MINOR_V13, 13)
        XCTAssertEqual(SWR_ABI_MINOR_V12, 12, "the 0.12 constant must not move")
        XCTAssertEqual([SWR_AXE_HEADER, SWR_AXE_LINK], [1, 2])
        XCTAssertEqual(BridgeRevision.v13.rawValue, 13)
        XCTAssertEqual(BridgeRevision.v13.description, "0.13")
    }

    private func bridge(_ revision: BridgeRevision) -> Bridge {
        var api = swr_api(); api.commit = fakeCommit
        var info = swr_bootstrap_info(); info.abi_minor = UInt32(revision.rawValue)
        return Bridge(api: api, info: info, revision: revision)
    }

    func testSupportFollowsTheRevision() {
        XCTAssertFalse(bridge(.v12).supportsAccessibilityExtras)
        XCTAssertTrue(bridge(.v13).supportsAccessibilityExtras)
        XCTAssertTrue(bridge(.v13).supportsPaths, "0.13 keeps 0.12 behaviour")
    }

    func testNegotiationMatrix() throws {
        func pick(_ b13: Bool, _ a13: Bool, _ b12: Bool = true, _ a12: Bool = true, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, hasBootstrapV08: true, hasApiV08: true,
                                         hasBootstrapV09: true, hasApiV09: true, hasBootstrapV10: true, hasApiV10: true,
                                         hasBootstrapV11: true, hasApiV11: true, hasBootstrapV12: b12, hasApiV12: a12,
                                         hasBootstrapV13: b13, hasApiV13: a13, minimum: min)
        }
        XCTAssertEqual(try pick(true, true), .v13)
        XCTAssertEqual(try pick(false, false), .v12, "a 0.13 bridge on a 0.12 renderer falls back")
        XCTAssertEqual(try pick(false, false, false, false), .v11)
        XCTAssertThrowsError(try pick(true, false), "half-exported 0.13")
        XCTAssertThrowsError(try pick(false, true), "half-exported 0.13")
        XCTAssertThrowsError(try pick(false, false, true, true, .v13)) {
            XCTAssertTrue(String(describing: $0).contains("requires 0.13"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.12"))
        }
    }

    private func info13() -> swr_bootstrap_info_v13 {
        var v = swr_bootstrap_info_v13()
        var base = v.v12.v11.v10.v09.v08.v07
        base.api_table_size = UInt32(MemoryLayout<swr_api_v08>.size)
        base.fn_count = UInt32(SWR_API_V08_FN_COUNT)
        base.abi_major = UInt32(SWR_ABI_MAJOR)
        base.abi_minor = UInt32(SWR_ABI_MINOR_V13)
        base.pointer_width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        withUnsafeMutableBytes(of: &base.arch) { raw in
            for (i, b) in Array("x86_64".utf8).enumerated() { raw[i] = b }
        }
        base.host_callbacks_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        base.transaction_size = UInt32(MemoryLayout<swr_transaction>.size)
        base.node_size = UInt32(MemoryLayout<swr_node>.size)
        base.primitive_size = UInt32(MemoryLayout<swr_primitive>.size)
        base.semantic_size = UInt32(MemoryLayout<swr_semantic>.size)
        base.ax_text_run_size = UInt32(MemoryLayout<swr_ax_text_run>.size)
        base.event_size = UInt32(MemoryLayout<swr_event>.size)
        base.measure_request_size = UInt32(MemoryLayout<swr_measure_request>.size)
        base.measure_result_size = UInt32(MemoryLayout<swr_measure_result>.size)
        base.line_info_size = UInt32(MemoryLayout<swr_line_info>.size)
        base.char_cell_size = UInt32(MemoryLayout<swr_char_cell>.size)
        base.stats_size = UInt32(MemoryLayout<swr_stats>.size)
        base.font_info_size = UInt32(MemoryLayout<swr_font_info>.size)
        base.font_resolution_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        v.v12.v11.v10.v09.v08.v07 = base
        v.v12.v11.v10.v09.v08.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        v.v12.v11.v10.v09.v08.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        v.v12.v11.v10.v09.v08.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        v.v12.v11.v10.v09.v08.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        v.v12.v11.v10.v09.v08.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        v.v12.v11.v10.v09.range_entry_size = UInt32(MemoryLayout<swr_range_entry>.size)
        v.v12.v11.v10.v09.transaction_v09_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
        v.v12.v11.v10.run_options_v10_size = UInt32(MemoryLayout<swr_run_options_v10>.size)
        v.v12.v11.wheel_delta = UInt32(SWR_WHEEL_DELTA)
        v.v12.path_entry_size = UInt32(MemoryLayout<swr_path_entry>.size)
        v.v12.transaction_v12_size = UInt32(MemoryLayout<swr_transaction_v12>.size)
        v.ax_extra_entry_size = UInt32(MemoryLayout<swr_ax_extra_entry>.size)
        v.transaction_v13_size = UInt32(MemoryLayout<swr_transaction_v13>.size)
        return v
    }

    func testValidateV13() throws {
        #if arch(x86_64)
        try BridgeNegotiation.validateV13(info13())
        #endif
        var a = info13(); a.v12.v11.v10.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V12)
        XCTAssertThrowsError(try BridgeNegotiation.validateV13(a), "a 0.12 minor is not a 0.13 view")
        var b = info13(); b.ax_extra_entry_size = 56
        XCTAssertThrowsError(try BridgeNegotiation.validateV13(b))
        var c = info13(); c.transaction_v13_size = 128
        XCTAssertThrowsError(try BridgeNegotiation.validateV13(c))
        var d = info13(); d.v12.path_entry_size = 28
        XCTAssertThrowsError(try BridgeNegotiation.validateV13(d))
    }

    private func upsert(_ id: UInt64, _ extras: SemanticExtras?) -> NodeUpsert {
        NodeUpsert(id: id, bounds: Rect(x: 0, y: 0, w: 10, h: 10),
                   semantic: SemanticNode(role: .staticText, label: "t", extras: extras))
    }

    func testMarshallingEncodesOnlyNodesWithContent() {
        let arena = Arena()
        let t = Transaction(version: 1, upserts: [
            upsert(1, SemanticExtras(hint: "Starts the scan", value: "ready", description: "d", isHeader: true, headingLevel: 3)),
            upsert(2, nil),
            upsert(3, SemanticExtras()),
            upsert(4, SemanticExtras(isLink: true, headingLevel: 4)),
            upsert(5, SemanticExtras(isHeader: true, headingLevel: 99)),
            upsert(6, SemanticExtras(isHeader: true)),
        ])
        let e = cAxExtras(t, arena: arena)
        XCTAssertEqual(e.map(\.id), [1, 4, 5, 6])
        XCTAssertEqual(text(e[0].help), "Starts the scan")
        XCTAssertEqual(text(e[0].value), "ready")
        XCTAssertEqual(text(e[0].description), "d")
        XCTAssertEqual(e[0].flags, SWR_AXE_HEADER)
        XCTAssertEqual(e[0].heading_level, 3)
        XCTAssertEqual(e[1].flags, SWR_AXE_LINK)
        XCTAssertEqual(e[1].heading_level, 0, "a level without the header trait would be refused, so it is not sent")
        XCTAssertEqual(e[2].heading_level, 6, "clamped")
        XCTAssertEqual(e[3].heading_level, 0, "unset: the renderer publishes 2")
    }

    func testLongStringsAreTruncatedAtACharacterBoundary() {
        let arena = Arena()
        let long = String(repeating: "\u{00e9}", count: Int(SWR_AX_EXTRA_STR_MAX))   // 2 bytes each
        let e = cAxExtras(Transaction(version: 1, upserts: [upsert(1, SemanticExtras(hint: long))]), arena: arena)
        XCTAssertLessThanOrEqual(e[0].help.len, SWR_AX_EXTRA_STR_MAX)
        XCTAssertEqual(text(e[0].help), String(repeating: "\u{00e9}", count: Int(SWR_AX_EXTRA_STR_MAX) / 2))
    }

    func testCommitCarriesTheTableOnlyOn013() throws {
        let t = Transaction(version: 1, upserts: [upsert(1, SemanticExtras(hint: "h", isLink: true)), upsert(2, nil)])
        seenStructSize = 0; seenExtras = []
        let b13 = bridge(.v13)   // BridgeWindow holds its bridge unowned: keep it alive
        try withExtendedLifetime(b13) { try BridgeWindow.makeForTesting(bridge: b13, handle: 1).commit(t) }
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction_v13>.size)
        XCTAssertEqual(seenExtras.count, 1)
        XCTAssertEqual(seenExtras[0].id, 1)
        XCTAssertEqual(seenExtras[0].help, "h")
        XCTAssertEqual(seenExtras[0].flags, SWR_AXE_LINK)

        seenStructSize = 0; seenExtras = []
        let b12 = bridge(.v12)
        try withExtendedLifetime(b12) { try BridgeWindow.makeForTesting(bridge: b12, handle: 1).commit(Transaction(version: 1, upserts: t.upserts)) }
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction_v12>.size, "a 0.12 renderer gets the 128-byte transaction, no extras")
        XCTAssertTrue(seenExtras.isEmpty)
    }
}
