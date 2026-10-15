import XCTest
@testable import SwiftRightBridge
import CSwiftRight

// ABI 0.9 (decision H1): slider role and numeric range. Layout, negotiation, validation and the transaction tail.

nonisolated(unsafe) private var seenStructSize: UInt32 = 0
nonisolated(unsafe) private var seenRanges: [swr_range_entry] = []
nonisolated(unsafe) private var seenRole: UInt32 = 0

private func fakeCommit(_ t: UnsafePointer<swr_transaction>?) -> Int32 {
    guard let t else { return -1 }
    seenStructSize = t.pointee.struct_size
    seenRole = t.pointee.upserts?.pointee.semantic.role ?? 0
    seenRanges = []
    if Int(t.pointee.struct_size) >= MemoryLayout<swr_transaction_v09>.size {
        t.withMemoryRebound(to: swr_transaction_v09.self, capacity: 1) { p in
            if let r = p.pointee.ranges {
                seenRanges = Array(UnsafeBufferPointer(start: r, count: Int(p.pointee.range_count)))
            }
        }
    }
    return 0
}

final class SliderRangeTests: XCTestCase {
    func testLayoutMatchesTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_range_entry>.size, 56)
        XCTAssertEqual(MemoryLayout<swr_transaction>.size, 72)
        XCTAssertEqual(MemoryLayout<swr_transaction_v09>.size, 88)
        XCTAssertEqual(MemoryLayout<swr_transaction_v09>.offset(of: \.ranges), 72)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v09>.size, 128)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v09>.offset(of: \.range_entry_size), 120)
        XCTAssertEqual(SWR_ABI_MINOR_V09, 9)
        XCTAssertEqual(SWR_ROLE_SLIDER, 15)
        XCTAssertEqual(NodeRole.slider.rawValue, UInt32(SWR_ROLE_SLIDER))
        XCTAssertEqual(SWR_RUN_POINTER_MOVES, 1)
        XCTAssertEqual(SWR_PTR_MOVE, 3)
        XCTAssertEqual(SWR_PTR_I0_LEFT_DOWN, 1)
        XCTAssertEqual(SWR_PTR_I0_LEFT_WINDOW, 2)
        XCTAssertFalse(bridge(.v08).supportsPointerMoves)
        XCTAssertTrue(bridge(.v09).supportsPointerMoves)
        XCTAssertEqual(SWR_ABI_MINOR, 6, "the legacy constant must not move")
    }

    func testNegotiationMatrix() throws {
        func pick(_ b9: Bool, _ a9: Bool, _ b8: Bool = true, _ a8: Bool = true, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, hasBootstrapV08: b8, hasApiV08: a8,
                                         hasBootstrapV09: b9, hasApiV09: a9, minimum: min)
        }
        XCTAssertEqual(try pick(true, true), .v09)
        XCTAssertEqual(try pick(false, false), .v08, "a 0.9 bridge on a 0.8 renderer falls back")
        XCTAssertEqual(try pick(false, false, false, false), .v07)
        XCTAssertThrowsError(try pick(true, false), "half-exported 0.9")
        XCTAssertThrowsError(try pick(false, true), "half-exported 0.9")
        XCTAssertThrowsError(try pick(false, false, true, true, .v09)) {
            XCTAssertTrue(String(describing: $0).contains("requires 0.9"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.8"))
        }
    }

    private func info09() -> swr_bootstrap_info_v09 {
        var v = swr_bootstrap_info_v07()
        v.struct_size = UInt32(MemoryLayout<swr_bootstrap_info_v09>.size)
        v.abi_major = UInt32(SWR_ABI_MAJOR)
        v.abi_minor = UInt32(SWR_ABI_MINOR_V09)
        v.pointer_width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        withUnsafeMutableBytes(of: &v.arch) { raw in for (n, b) in "x86_64".utf8.enumerated() { raw[n] = b } }
        v.host_callbacks_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        v.api_table_size = UInt32(MemoryLayout<swr_api_v08>.size)
        v.transaction_size = UInt32(MemoryLayout<swr_transaction>.size)
        v.node_size = UInt32(MemoryLayout<swr_node>.size)
        v.primitive_size = UInt32(MemoryLayout<swr_primitive>.size)
        v.semantic_size = UInt32(MemoryLayout<swr_semantic>.size)
        v.ax_text_run_size = UInt32(MemoryLayout<swr_ax_text_run>.size)
        v.event_size = UInt32(MemoryLayout<swr_event>.size)
        v.measure_request_size = UInt32(MemoryLayout<swr_measure_request>.size)
        v.measure_result_size = UInt32(MemoryLayout<swr_measure_result>.size)
        v.line_info_size = UInt32(MemoryLayout<swr_line_info>.size)
        v.char_cell_size = UInt32(MemoryLayout<swr_char_cell>.size)
        v.fn_count = UInt32(SWR_API_V08_FN_COUNT)
        v.stats_size = UInt32(MemoryLayout<swr_stats>.size)
        v.font_info_size = UInt32(MemoryLayout<swr_font_info>.size)
        v.font_resolution_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        var i8 = swr_bootstrap_info_v08()
        i8.v07 = v
        i8.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        i8.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        i8.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        i8.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        i8.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        var i = swr_bootstrap_info_v09()
        i.v08 = i8
        i.range_entry_size = UInt32(MemoryLayout<swr_range_entry>.size)
        i.transaction_v09_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
        return i
    }

    func testValidateV09() throws {
        try BridgeNegotiation.validateV09(info09())
        var a = info09(); a.v08.v07.base_minorFix(8)
        XCTAssertThrowsError(try BridgeNegotiation.validateV09(a), "a 0.8 minor is not a 0.9 view")
        var b = info09(); b.range_entry_size = 48
        XCTAssertThrowsError(try BridgeNegotiation.validateV09(b))
        var c = info09(); c.transaction_v09_size = 72
        XCTAssertThrowsError(try BridgeNegotiation.validateV09(c))
        var d = info09(); d.v08.v07.api_table_size = 152
        XCTAssertThrowsError(try BridgeNegotiation.validateV09(d))
    }

    private func bridge(_ revision: BridgeRevision) -> Bridge {
        var api = swr_api(); api.commit = fakeCommit
        var info = swr_bootstrap_info(); info.abi_minor = UInt32(revision.rawValue)
        return Bridge(api: api, info: info, revision: revision)
    }

    private func sliderTx() -> Transaction {
        let sem = SemanticNode(role: .slider, label: "Watch limit",
                               range: SliderRange(value: 40, min: 0, max: 100, step: 1, jump: 10))
        let text = SemanticNode(role: .staticText, label: "x")
        return Transaction(version: 1, upserts: [
            NodeUpsert(id: 1, bounds: Rect(x: 0, y: 0, w: 10, h: 10), semantic: sem),
            NodeUpsert(id: 2, bounds: Rect(x: 0, y: 0, w: 10, h: 10), semantic: text),
        ])
    }

    func testCommitCarriesTheRangeTableOn09() throws {
        seenStructSize = 0; seenRanges = []
        let b = bridge(.v09)
        XCTAssertTrue(b.supportsSliderRange)
        try BridgeWindow.makeForTesting(bridge: b, handle: 1).commit(sliderTx())
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction_v09>.size)
        XCTAssertEqual(seenRole, 15)
        XCTAssertEqual(seenRanges.count, 1)
        XCTAssertEqual(seenRanges[0].id, 1)
        XCTAssertEqual([seenRanges[0].value, seenRanges[0].min, seenRanges[0].max, seenRanges[0].step, seenRanges[0].jump], [40, 0, 100, 1, 10])
    }

    func testCommitIsTheOldShapeBefore09() throws {
        seenStructSize = 0; seenRanges = []
        let b = bridge(.v08)
        XCTAssertFalse(b.supportsSliderRange)
        try BridgeWindow.makeForTesting(bridge: b, handle: 1).commit(sliderTx())
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction>.size, "a 0.8 renderer gets the 72-byte transaction")
        XCTAssertTrue(seenRanges.isEmpty)
    }
}

private extension swr_bootstrap_info_v07 {
    mutating func base_minorFix(_ m: UInt32) { abi_minor = m }
}
