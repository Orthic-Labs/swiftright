import XCTest
@testable import SwiftRightBridge
import CSwiftRight

// ABI 0.10 (decision H17): explicit render scale. Layout, negotiation, validation, the run options on the wire and the one
// scale source for measurement. Window size, hit-testing and UIA bounds follow the scale in the renderer (render/swiftright-render
// src/scale.rs tests); this file covers everything the Swift side decides.

nonisolated(unsafe) private var seenMeasureScale: Float = 0

private func fakeMeasure(_ r: UnsafePointer<swr_measure_request>?, _ out: UnsafeMutablePointer<swr_measure_result>?) -> Int32 {
    seenMeasureScale = r?.pointee.scale ?? -1
    return 0
}

final class RenderScaleTests: XCTestCase {
    func testLayoutMatchesTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_run_options>.size, 40)
        XCTAssertEqual(MemoryLayout<swr_run_options_v10>.size, 48)
        XCTAssertEqual(MemoryLayout<swr_run_options_v10>.offset(of: \.render_scale), 40)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v10>.size, 136)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v10>.offset(of: \.run_options_v10_size), 128)
        XCTAssertEqual(SWR_ABI_MINOR_V10, 10)
        XCTAssertEqual(SWR_ABI_MINOR_V09, 9, "the 0.9 constant must not move")
        XCTAssertEqual(SWR_ABI_MINOR, 6, "the legacy constant must not move")
        XCTAssertEqual(BridgeRevision.v10.rawValue, 10)
        XCTAssertEqual(BridgeRevision.v10.description, "0.10")
    }

    private func bridge(_ revision: BridgeRevision) -> Bridge {
        var api = swr_api(); api.measure_text = fakeMeasure
        var info = swr_bootstrap_info(); info.abi_minor = UInt32(revision.rawValue)
        return Bridge(api: api, info: info, revision: revision)
    }

    func testSupportFollowsTheRevision() {
        XCTAssertFalse(bridge(.v09).supportsRenderScale)
        XCTAssertTrue(bridge(.v10).supportsRenderScale)
        XCTAssertTrue(bridge(.v10).supportsSliderRange, "0.10 keeps 0.9 behaviour")
        XCTAssertTrue(bridge(.v10).supportsPointerMoves)
    }

    func testNegotiationMatrix() throws {
        func pick(_ b10: Bool, _ a10: Bool, _ b9: Bool = true, _ a9: Bool = true, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, hasBootstrapV08: true, hasApiV08: true,
                                         hasBootstrapV09: b9, hasApiV09: a9, hasBootstrapV10: b10, hasApiV10: a10, minimum: min)
        }
        XCTAssertEqual(try pick(true, true), .v10)
        XCTAssertEqual(try pick(false, false), .v09, "a 0.10 bridge on a 0.9 renderer falls back")
        XCTAssertEqual(try pick(false, false, false, false), .v08)
        XCTAssertThrowsError(try pick(true, false), "half-exported 0.10")
        XCTAssertThrowsError(try pick(false, true), "half-exported 0.10")
        XCTAssertThrowsError(try pick(false, false, true, true, .v10)) {
            XCTAssertTrue(String(describing: $0).contains("requires 0.10"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.9"))
        }
    }

    private func info10() -> swr_bootstrap_info_v10 {
        var v = swr_bootstrap_info_v10()
        v.v09.v08.v07.api_table_size = UInt32(MemoryLayout<swr_api_v08>.size)
        v.v09.v08.v07.fn_count = UInt32(SWR_API_V08_FN_COUNT)
        v.v09.v08.v07.abi_major = UInt32(SWR_ABI_MAJOR)
        v.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V10)
        v.v09.v08.v07.pointer_width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        withUnsafeMutableBytes(of: &v.v09.v08.v07.arch) { raw in
            for (i, b) in Array("x86_64".utf8).enumerated() { raw[i] = b }
        }
        v.v09.v08.v07.host_callbacks_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        v.v09.v08.v07.transaction_size = UInt32(MemoryLayout<swr_transaction>.size)
        v.v09.v08.v07.node_size = UInt32(MemoryLayout<swr_node>.size)
        v.v09.v08.v07.primitive_size = UInt32(MemoryLayout<swr_primitive>.size)
        v.v09.v08.v07.semantic_size = UInt32(MemoryLayout<swr_semantic>.size)
        v.v09.v08.v07.ax_text_run_size = UInt32(MemoryLayout<swr_ax_text_run>.size)
        v.v09.v08.v07.event_size = UInt32(MemoryLayout<swr_event>.size)
        v.v09.v08.v07.measure_request_size = UInt32(MemoryLayout<swr_measure_request>.size)
        v.v09.v08.v07.measure_result_size = UInt32(MemoryLayout<swr_measure_result>.size)
        v.v09.v08.v07.line_info_size = UInt32(MemoryLayout<swr_line_info>.size)
        v.v09.v08.v07.char_cell_size = UInt32(MemoryLayout<swr_char_cell>.size)
        v.v09.v08.v07.stats_size = UInt32(MemoryLayout<swr_stats>.size)
        v.v09.v08.v07.font_info_size = UInt32(MemoryLayout<swr_font_info>.size)
        v.v09.v08.v07.font_resolution_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        v.v09.v08.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        v.v09.v08.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        v.v09.v08.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        v.v09.v08.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        v.v09.v08.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        v.v09.range_entry_size = UInt32(MemoryLayout<swr_range_entry>.size)
        v.v09.transaction_v09_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
        v.run_options_v10_size = UInt32(MemoryLayout<swr_run_options_v10>.size)
        return v
    }

    func testValidateV10() throws {
        #if arch(x86_64)
        try BridgeNegotiation.validateV10(info10())
        #endif
        var a = info10(); a.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V09)
        XCTAssertThrowsError(try BridgeNegotiation.validateV10(a), "a 0.9 minor is not a 0.10 view")
        var b = info10(); b.run_options_v10_size = 40
        XCTAssertThrowsError(try BridgeNegotiation.validateV10(b))
        var c = info10(); c.v09.transaction_v09_size = 72
        XCTAssertThrowsError(try BridgeNegotiation.validateV10(c))
    }

    // MARK: no override is the old behaviour

    func testNoRenderScaleSendsTheOldOptions() throws {
        XCTAssertEqual(try Bridge.runOptionsScale(requested: nil, rendererSupports: false, revision: .v09), 0,
                       "no scale needs no 0.10 renderer")
        XCTAssertEqual(try Bridge.runOptionsScale(requested: nil, rendererSupports: true, revision: .v10), 0)
        let none = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 320, height: 240, pointerMoves: true, renderScale: 0)
        XCTAssertEqual(Int(none.base.struct_size), MemoryLayout<swr_run_options>.size, "the renderer sees the 0.9-sized struct")
        XCTAssertEqual(none.render_scale, 0)
        XCTAssertEqual(none.base.width_dip, 320)
        XCTAssertEqual(none.base.height_dip, 240)
        XCTAssertEqual(none.base.flags, UInt32(SWR_RUN_POINTER_MOVES))
        // The measurement scale is the request's own.
        XCTAssertEqual(Bridge.measureScale(requested: 1.25, renderScale: nil), 1.25)
    }

    // MARK: an override travels and wins

    func testRenderScaleIsCarriedInTheTail() throws {
        XCTAssertEqual(try Bridge.runOptionsScale(requested: 2.5, rendererSupports: true, revision: .v10), 2.5)
        let o = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 320, height: 240, pointerMoves: false, renderScale: 2.5)
        XCTAssertEqual(Int(o.base.struct_size), MemoryLayout<swr_run_options_v10>.size)
        XCTAssertEqual(o.render_scale, 2.5)
        XCTAssertEqual(o.base.width_dip, 320, "the window is still asked for in DIPs: the renderer multiplies by the scale")
        XCTAssertEqual(o.base.flags, 0)
        // The base fields are identical with and without the scale.
        let plain = Bridge.makeRunOptions(title: nil, titleLen: 0, wake: nil, width: 320, height: 240, pointerMoves: false, renderScale: 0)
        XCTAssertEqual(plain.base.width_dip, o.base.width_dip)
        XCTAssertEqual(plain.base.height_dip, o.base.height_dip)
        XCTAssertEqual(plain.base.flags, o.base.flags)
    }

    func testAnUnsupportedOrInvalidScaleThrowsInsteadOfBeingDropped() {
        XCTAssertThrowsError(try Bridge.runOptionsScale(requested: 2.5, rendererSupports: false, revision: .v09)) {
            XCTAssertTrue(String(describing: $0).contains("needs 0.10"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.9"))
        }
        for bad: Float in [.nan, .infinity, -1, 0, 0.1, 16.5] {
            XCTAssertThrowsError(try Bridge.runOptionsScale(requested: bad, rendererSupports: true, revision: .v10), "\(bad)")
        }
        XCTAssertNoThrow(try Bridge.runOptionsScale(requested: 0.25, rendererSupports: true, revision: .v10))
        XCTAssertNoThrow(try Bridge.runOptionsScale(requested: 16, rendererSupports: true, revision: .v10))
    }

    func testRunThrowsOnAnOldRendererBeforeTouchingAnything() {
        let b = bridge(.v09)
        XCTAssertThrowsError(try b.run(title: "t", width: 320, height: 240, renderScale: 2.5))
        XCTAssertNil(b.renderScale, "a refused scale is not recorded")
    }

    func testMeasurementUsesTheRenderScaleWhateverTheRequestSays() throws {
        let b = bridge(.v10)
        let request = MeasureRequest(text: "x", scale: 1.25)
        seenMeasureScale = 0
        _ = try? b.measure(request)
        XCTAssertEqual(seenMeasureScale, 1.25, "no override: the request's own scale reaches the renderer")
        b.renderScale = 2.5
        seenMeasureScale = 0
        _ = try? b.measure(request)
        XCTAssertEqual(seenMeasureScale, 2.5, "with an override the one scale source wins")
        XCTAssertEqual(Bridge.measureScale(requested: 1.0, renderScale: 2.5), 2.5)
    }

    /// The scale a host lays out with is the one in the metrics event, which the renderer fills with the render scale on any display
    /// (and, on WM_DPICHANGED, keeps). The latch must report it, not anything derived from a DPI.
    func testTheMetricsLatchReportsTheEventScale() {
        var latch = MetricsLatch()
        let ev = BridgeEvent(kindRaw: BridgeEvent.Kind.windowMetrics.rawValue, x: 2.5, i0: 800, i1: 600)
        XCTAssertTrue(latch.apply(ev))
        let got = latch.resolve(getter: (width: 400, height: 300, scale: 1.25, active: true))
        XCTAssertEqual(got.width, 800)
        XCTAssertEqual(got.height, 600)
        XCTAssertEqual(got.scale, 2.5)
    }
}
