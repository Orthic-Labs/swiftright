import XCTest
@testable import SwiftRightBridge
import CSwiftRight

// ABI 0.11 (issue #31): pointer wheel and the scroll bar role. Layout, negotiation, validation, the opt-in on the wire, event
// decoding and the range table for a scroll bar node. The renderer side (WM_MOUSEWHEEL decoding, consumption, UIA ScrollBar) is
// covered by render/swiftright-render src/view.rs `wheel_tests`, src/tree.rs `scroll_bar_range_table` and src/lib.rs
// `bootstrap_v11_extends_v10_and_reports_minor_11`.

final class ScrollWheelTests: XCTestCase {
    func testLayoutMatchesTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v10>.size, 136)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v11>.size, 144)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v11>.offset(of: \.wheel_delta), 136)
        XCTAssertEqual(MemoryLayout<swr_event>.size, 136, "the event struct does not grow")
        XCTAssertEqual(SWR_ABI_MINOR_V11, 11)
        XCTAssertEqual(SWR_ABI_MINOR_V10, 10, "the 0.10 constant must not move")
        XCTAssertEqual(SWR_PTR_WHEEL, 4)
        XCTAssertEqual(SWR_PTR_MOVE, 3)
        XCTAssertEqual(SWR_RUN_POINTER_WHEEL, 0x2)
        XCTAssertEqual(SWR_RUN_POINTER_MOVES, 0x1)
        XCTAssertEqual(SWR_WHEEL_DELTA, 120)
        XCTAssertEqual(SWR_MOD_PRECISE, 0x100)
        XCTAssertEqual(SWR_ROLE_SCROLL_BAR, 16)
        XCTAssertEqual(NodeRole.scrollBar.rawValue, UInt32(SWR_ROLE_SCROLL_BAR))
        XCTAssertEqual(BridgeRevision.v11.rawValue, 11)
        XCTAssertEqual(BridgeRevision.v11.description, "0.11")
    }

    private func bridge(_ revision: BridgeRevision) -> Bridge {
        var info = swr_bootstrap_info(); info.abi_minor = UInt32(revision.rawValue)
        return Bridge(api: swr_api(), info: info, revision: revision)
    }

    func testSupportFollowsTheRevision() {
        XCTAssertFalse(bridge(.v10).supportsPointerWheel)
        XCTAssertFalse(bridge(.v10).supportsScrollBar)
        XCTAssertTrue(bridge(.v11).supportsPointerWheel)
        XCTAssertTrue(bridge(.v11).supportsScrollBar)
        XCTAssertTrue(bridge(.v11).supportsRenderScale, "0.11 keeps 0.10 behaviour")
        XCTAssertTrue(bridge(.v11).supportsPointerMoves)
    }

    func testNegotiationMatrix() throws {
        func pick(_ b11: Bool, _ a11: Bool, _ b10: Bool = true, _ a10: Bool = true, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, hasBootstrapV08: true, hasApiV08: true,
                                         hasBootstrapV09: true, hasApiV09: true, hasBootstrapV10: b10, hasApiV10: a10,
                                         hasBootstrapV11: b11, hasApiV11: a11, minimum: min)
        }
        XCTAssertEqual(try pick(true, true), .v11)
        XCTAssertEqual(try pick(false, false), .v10, "a 0.11 bridge on a 0.10 renderer falls back")
        XCTAssertEqual(try pick(false, false, false, false), .v09)
        XCTAssertThrowsError(try pick(true, false), "half-exported 0.11")
        XCTAssertThrowsError(try pick(false, true), "half-exported 0.11")
        XCTAssertThrowsError(try pick(false, false, true, true, .v11)) {
            XCTAssertTrue(String(describing: $0).contains("requires 0.11"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.10"))
        }
    }

    private func info11() -> swr_bootstrap_info_v11 {
        var v = swr_bootstrap_info_v11()
        v.v10.v09.v08.v07.api_table_size = UInt32(MemoryLayout<swr_api_v08>.size)
        v.v10.v09.v08.v07.fn_count = UInt32(SWR_API_V08_FN_COUNT)
        v.v10.v09.v08.v07.abi_major = UInt32(SWR_ABI_MAJOR)
        v.v10.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V11)
        v.v10.v09.v08.v07.pointer_width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        withUnsafeMutableBytes(of: &v.v10.v09.v08.v07.arch) { raw in
            for (i, b) in Array("x86_64".utf8).enumerated() { raw[i] = b }
        }
        v.v10.v09.v08.v07.host_callbacks_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        v.v10.v09.v08.v07.transaction_size = UInt32(MemoryLayout<swr_transaction>.size)
        v.v10.v09.v08.v07.node_size = UInt32(MemoryLayout<swr_node>.size)
        v.v10.v09.v08.v07.primitive_size = UInt32(MemoryLayout<swr_primitive>.size)
        v.v10.v09.v08.v07.semantic_size = UInt32(MemoryLayout<swr_semantic>.size)
        v.v10.v09.v08.v07.ax_text_run_size = UInt32(MemoryLayout<swr_ax_text_run>.size)
        v.v10.v09.v08.v07.event_size = UInt32(MemoryLayout<swr_event>.size)
        v.v10.v09.v08.v07.measure_request_size = UInt32(MemoryLayout<swr_measure_request>.size)
        v.v10.v09.v08.v07.measure_result_size = UInt32(MemoryLayout<swr_measure_result>.size)
        v.v10.v09.v08.v07.line_info_size = UInt32(MemoryLayout<swr_line_info>.size)
        v.v10.v09.v08.v07.char_cell_size = UInt32(MemoryLayout<swr_char_cell>.size)
        v.v10.v09.v08.v07.stats_size = UInt32(MemoryLayout<swr_stats>.size)
        v.v10.v09.v08.v07.font_info_size = UInt32(MemoryLayout<swr_font_info>.size)
        v.v10.v09.v08.v07.font_resolution_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        v.v10.v09.v08.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        v.v10.v09.v08.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        v.v10.v09.v08.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        v.v10.v09.v08.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        v.v10.v09.v08.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        v.v10.v09.range_entry_size = UInt32(MemoryLayout<swr_range_entry>.size)
        v.v10.v09.transaction_v09_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
        v.v10.run_options_v10_size = UInt32(MemoryLayout<swr_run_options_v10>.size)
        v.wheel_delta = UInt32(SWR_WHEEL_DELTA)
        return v
    }

    func testValidateV11() throws {
        #if arch(x86_64)
        try BridgeNegotiation.validateV11(info11())
        #endif
        var a = info11(); a.v10.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V10)
        XCTAssertThrowsError(try BridgeNegotiation.validateV11(a), "a 0.10 minor is not a 0.11 view")
        var b = info11(); b.wheel_delta = 60
        XCTAssertThrowsError(try BridgeNegotiation.validateV11(b))
        var c = info11(); c.v10.run_options_v10_size = 40
        XCTAssertThrowsError(try BridgeNegotiation.validateV11(c))
    }

    // MARK: the opt-in on the wire (the same mechanism as pointer moves)

    func testWheelOptInIsAFlagBitAndOldHostsSeeNothing() {
        let none = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 1, height: 1, pointerMoves: false, renderScale: 0)
        XCTAssertEqual(none.base.flags, 0, "a host that does not ask sends flags 0")
        let moves = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 1, height: 1, pointerMoves: true, renderScale: 0)
        XCTAssertEqual(moves.base.flags, UInt32(SWR_RUN_POINTER_MOVES), "the 0.9 flags are unchanged")
        let wheel = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 1, height: 1, pointerMoves: false, renderScale: 0,
                                          pointerWheel: true)
        XCTAssertEqual(wheel.base.flags, UInt32(SWR_RUN_POINTER_WHEEL))
        XCTAssertEqual(Int(wheel.base.struct_size), MemoryLayout<swr_run_options>.size, "no options tail for the wheel")
        let both = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 1, height: 1, pointerMoves: true, renderScale: 0,
                                         pointerWheel: true)
        XCTAssertEqual(both.base.flags, UInt32(SWR_RUN_POINTER_MOVES) | UInt32(SWR_RUN_POINTER_WHEEL))
    }

    // MARK: decoding

    func testDecodeWheelEvent() {
        var e = swr_event()
        e.kind = UInt32(SWR_EV_POINTER); e.action = UInt32(SWR_PTR_WHEEL)
        e.node = 7; e.x = 120.5; e.y = 64
        e.i0 = -120; e.i1 = 0
        e.modifiers = UInt32(SWR_MOD_CTRL)
        let ev = decodeEvent(e)
        XCTAssertEqual(ev.wheel, BridgeEvent.Wheel(x: 120.5, y: 64, deltaY: -120, deltaX: 0, precise: false, node: 7,
                                                   modifiers: UInt32(SWR_MOD_CTRL)))
        e.i0 = 30; e.modifiers = UInt32(SWR_MOD_PRECISE) | UInt32(SWR_MOD_SHIFT)
        let p = decodeEvent(e).wheel
        XCTAssertEqual(p?.precise, true)
        XCTAssertEqual(p?.deltaY, 30)
        XCTAssertEqual(p?.modifiers, UInt32(SWR_MOD_SHIFT), "the precise bit is lifted out of the modifiers")
        e.action = UInt32(SWR_PTR_MOVE)
        XCTAssertNil(decodeEvent(e).wheel, "a move is not a wheel event")
        e.action = UInt32(SWR_PTR_WHEEL); e.kind = UInt32(SWR_EV_KEY)
        XCTAssertNil(decodeEvent(e).wheel, "only a pointer event can be a wheel event")
        let built = BridgeEvent.wheel(x: 1, y: 2, deltaY: 240, deltaX: -120, precise: false)
        XCTAssertEqual(built.wheel?.deltaY, 240)
        XCTAssertEqual(built.wheel?.deltaX, -120)
    }

    func testWheelScrollSettingMapping() {
        XCTAssertEqual(Bridge.wheelScrollSetting(raw: nil).lines, 3)
        XCTAssertEqual(Bridge.wheelScrollSetting(raw: 5).lines, 5)
        XCTAssertEqual(Bridge.wheelScrollSetting(raw: 0).lines, 0, "0 = wheel scrolling off")
        XCTAssertTrue(Bridge.wheelScrollSetting(raw: UInt32.max).page)
        XCTAssertEqual(Bridge.wheelScrollSetting(raw: UInt32.max).lines, 3)
        XCTAssertEqual(Bridge.wheelScrollSetting(raw: 99999).lines, 3)
        XCTAssertFalse(Bridge.wheelScrollSetting(raw: 3).page)
    }

    // MARK: the scroll bar range

    private func scrollBarTx() -> Transaction {
        let sem = SemanticNode(role: .scrollBar, label: "Vertical scroll bar",
                               range: SliderRange(value: 0.25, min: 0, max: 1, step: 0, jump: 0))
        return Transaction(version: 1, upserts: [
            NodeUpsert(id: 5, parent: 1, bounds: Rect(x: 380, y: 0, w: 19, h: 300), semantic: sem),
        ])
    }

    func testScrollBarRangeTravelsOnlyToARendererThatKnowsTheRole() {
        let on = cRanges(scrollBarTx(), scrollBars: true)
        XCTAssertEqual(on.count, 1)
        XCTAssertEqual(on.first?.id, 5)
        XCTAssertEqual(on.first?.value, 0.25)
        XCTAssertEqual(on.first?.min, 0)
        XCTAssertEqual(on.first?.max, 1)
        XCTAssertTrue(cRanges(scrollBarTx(), scrollBars: false).isEmpty, "a 0.10 renderer would refuse the commit for it")
        XCTAssertEqual(cRanges(scrollBarTx()).count, 1)
    }
}
