import CSwiftRight
import Foundation
import XCTest
@testable import SwiftRightBridge

// ABI 0.8 text extension (minimal form): layouts, negotiation matrix, marshalling and refusal logic through fake entry
// points (no DLL), so they run on every host. The Windows DLL pair (0.7 host on a 0.8 renderer, 0.8 host on a 0.7
// renderer) is exercised by factory/abi/abi08-dll-harness.ps1.

private nonisolated(unsafe) var seenRequest = swr_measure_request_v08()
private nonisolated(unsafe) var seenFeatures: [swr_feature] = []
private nonisolated(unsafe) var seenFallbacks: [String] = []
private nonisolated(unsafe) var v08Calls = 0
private nonisolated(unsafe) var legacyCalls = 0

private let fakeMeasureV08: MeasureV08Fn = { req, out in
    guard let req, let out else { return -1 }
    v08Calls += 1
    seenRequest = req.pointee
    seenFeatures = (0..<Int(req.pointee.feature_count)).map { req.pointee.features![$0] }
    seenFallbacks = (0..<Int(req.pointee.fallback_count)).map { i in
        let s = req.pointee.fallbacks![i]
        return String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(s.ptr!).assumingMemoryBound(to: UInt8.self), count: Int(s.len)), as: UTF8.self)
    }
    if out.pointee.struct_size < UInt32(MemoryLayout<swr_measure_result_v08>.size) { return -14 }
    // line buffer: one line
    if req.pointee.base.lines_cap > 0, let lines = req.pointee.base.lines_out {
        lines[0] = swr_line_info(utf8_start: 0, utf8_len: req.pointee.base.text_len, width: 40, top: 0, baseline: 12, reserved: 0)
    }
    out.pointee.base.run = (1 << 32) | 7
    out.pointee.base.width = 40
    out.pointee.base.height = 30
    out.pointee.base.first_baseline = 12
    out.pointee.base.last_baseline = 12
    out.pointee.base.line_count = 1
    out.pointee.base.lines_written = 1
    out.pointee.base.char_count = req.pointee.base.text_len
    out.pointee.applied = UInt32(SWR_M08_APPLIED_FEATURES | SWR_M08_APPLIED_TRACKING)
    out.pointee.ignored = UInt32(SWR_M08_IGN_OPSZ | SWR_M08_IGN_WEIGHT_SNAPPED)
    out.pointee.resolved_weight = 600
    out.pointee.resolved_italic = 0
    out.pointee.simulations = UInt32(SWR_SIMFLAG_BOLD)
    return 0
}

private let fakeRunFaces: RunFacesFn = { run, faces, cap, count in
    guard let count else { return -1 }
    count.pointee = 2
    guard let faces else { return 0 }
    func fill(_ i: Int, family: String, flags: UInt32, notdef: UInt32) {
        var f = swr_run_face()
        f.utf8_start = UInt32(i * 3); f.utf8_len = 3; f.glyph_count = 3; f.notdef_count = notdef
        f.flags = flags; f.weight = 400; f.ascent = 40; f.descent = 10; f.advance = 55
        withUnsafeMutableBytes(of: &f.sha256) { raw in if flags & UInt32(SWR_RUNFACE_BUNDLED) != 0 { for k in 0..<32 { raw[k] = UInt8(k) } } }
        setCString(&f.family, family)
        setCString(&f.ps_name, "\(family)-Regular")
        faces[i] = f
    }
    if cap > 0 { fill(0, family: "Tinos", flags: UInt32(SWR_RUNFACE_PRIMARY | SWR_RUNFACE_BUNDLED), notdef: 0) }
    if cap > 1 { fill(1, family: "", flags: UInt32(SWR_RUNFACE_FALLBACK | SWR_RUNFACE_UNRESOLVED), notdef: 1) }
    return 0
}

private let fakeFaceMetrics: FaceMetricsFn = { family, len, weight, width, italic, out in
    guard let family, let out else { return -1 }
    let name = String(decoding: UnsafeBufferPointer(start: family, count: Int(len)), as: UTF8.self)
    if out.pointee.struct_size < UInt32(MemoryLayout<swr_face_metrics>.size) { return -14 }
    guard name == "Tinos" else { out.pointee.flags = 0; return 0 }
    out.pointee.flags = UInt32(SWR_FACE_FOUND | SWR_FACE_BUNDLED)
    out.pointee.weight = 400
    out.pointee.source = UInt32(SWR_FONT_SRC_BUNDLED)
    out.pointee.units_per_em = 2048
    out.pointee.hhea_ascent = 1825; out.pointee.hhea_descent = -443; out.pointee.hhea_line_gap = 87
    out.pointee.axis_count = 1
    withUnsafeMutableBytes(of: &out.pointee.axes) { raw in
        raw.bindMemory(to: swr_axis_range.self)[0] = swr_axis_range(tag: OpenTypeFeature("wght").tag, min_value: 300, max_value: 700, default_value: 400)
    }
    setCString(&out.pointee.family, "Tinos")
    return 0
}

private let fakeSystemInfo: SystemFontInfoFn = { out in
    guard let out else { return -1 }
    out.pointee.flags = UInt32(SWR_SYSFONT_SEGOE_UI | SWR_SYSFONT_SITKA)
    out.pointee.family_count = 321
    withUnsafeMutableBytes(of: &out.pointee.entries) { raw in
        let e = raw.bindMemory(to: swr_system_font_entry.self)
        e[0].present = 1; e[0].face_count = 12
        setCString(&e[0].name, "Segoe UI"); setCString(&e[0].version, "Version 1.23")
        setCString(&e[1].name, "Segoe UI Variable Text")
    }
    return 0
}

private let fakeLegacyMeasure: @convention(c) (UnsafePointer<swr_measure_request>?, UnsafeMutablePointer<swr_measure_result>?) -> Int32 = { req, out in
    guard let req, let out else { return -1 }
    legacyCalls += 1
    if req.pointee.lines_cap > 0, let lines = req.pointee.lines_out {
        lines[0] = swr_line_info(utf8_start: 0, utf8_len: req.pointee.text_len, width: 40, top: 0, baseline: 12, reserved: 0)
    }
    out.pointee.run = (1 << 32) | 3
    out.pointee.line_count = 1
    out.pointee.lines_written = 1
    return 0
}

private let fakeFontRegister: FontRegisterFn = { _, _, _ in 0 }
private let fakeFontResolve: FontResolveFn = { _, _, _ in 0 }

final class TextExtensionTests: XCTestCase {
    override func setUp() { v08Calls = 0; legacyCalls = 0; seenFeatures = []; seenFallbacks = [] }

    private func info08() -> swr_bootstrap_info_v08 {
        var i = swr_bootstrap_info_v08()
        var v = swr_bootstrap_info_v07()
        v.struct_size = UInt32(MemoryLayout<swr_bootstrap_info_v08>.size)
        v.abi_major = UInt32(SWR_ABI_MAJOR)
        v.abi_minor = UInt32(SWR_ABI_MINOR_V08)
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
        i.v07 = v
        i.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        i.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        i.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        i.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        i.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        return i
    }

    private func ext() -> TextExtensionEntryPoints {
        TextExtensionEntryPoints(measure: fakeMeasureV08, runFaces: fakeRunFaces, faceMetrics: fakeFaceMetrics, systemFontInfo: fakeSystemInfo)
    }

    private func bridge08() -> Bridge {
        var api = swr_api(); api.measure_text = fakeLegacyMeasure; api.text_run_release = { _ in 0 }
        return Bridge(api: api, info: BridgeNegotiation.baseView(of: info08().v07), revision: .v08,
                      fonts: FontEntryPoints(register: fakeFontRegister, resolve: fakeFontResolve), textExtension: ext())
    }

    /// A 0.7 renderer: no text extension.
    private func bridge07() -> Bridge {
        var api = swr_api(); api.measure_text = fakeLegacyMeasure; api.text_run_release = { _ in 0 }
        return Bridge(api: api, info: swr_bootstrap_info(), revision: .v07,
                      fonts: FontEntryPoints(register: fakeFontRegister, resolve: fakeFontResolve))
    }

    private func req(_ e: TextExtension? = nil) -> MeasureRequest {
        MeasureRequest(text: "Hello", fontFamily: "Tinos", weight: 400, fontSize: 18, lineHeight: 20, scale: 2.5, extension: e)
    }

    // MARK: layouts (the same numbers as factory/abi/abi-0.8-layout-mock.c and the renderer's abi.rs)

    func testLayoutsMatchTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info>.size, 88)
        XCTAssertEqual(MemoryLayout<swr_api>.size, 136)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v07>.size, 96)
        XCTAssertEqual(MemoryLayout<swr_api_v07>.size, 152)
        XCTAssertEqual(MemoryLayout<swr_feature>.size, 8)
        XCTAssertEqual(MemoryLayout<swr_str>.size, 16)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.size, 160)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.alignment, 8)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.base), 8)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.weight_f), 96)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.tracking_dip), 112)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.baseline_offset_dip), 120)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.simulations), 128)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.features), 136)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.fallbacks), 144)
        XCTAssertEqual(MemoryLayout<swr_measure_request_v08>.offset(of: \.fallback_count), 152)
        XCTAssertEqual(MemoryLayout<swr_measure_result_v08>.size, 88)
        XCTAssertEqual(MemoryLayout<swr_measure_result_v08>.offset(of: \.applied), 64)
        XCTAssertEqual(MemoryLayout<swr_measure_result_v08>.offset(of: \.simulations), 80)
        XCTAssertEqual(MemoryLayout<swr_run_face>.size, 296)
        XCTAssertEqual(MemoryLayout<swr_run_face>.offset(of: \.sha256), 40)
        XCTAssertEqual(MemoryLayout<swr_run_face>.offset(of: \.family), 72)
        XCTAssertEqual(MemoryLayout<swr_run_face>.offset(of: \.file_name), 232)
        XCTAssertEqual(MemoryLayout<swr_axis_range>.size, 16)
        XCTAssertEqual(MemoryLayout<swr_face_metrics>.size, 456)
        XCTAssertEqual(MemoryLayout<swr_face_metrics>.offset(of: \.axes), 72)
        XCTAssertEqual(MemoryLayout<swr_face_metrics>.offset(of: \.family), 232)
        XCTAssertEqual(MemoryLayout<swr_face_metrics>.offset(of: \.file_name), 392)
        XCTAssertEqual(MemoryLayout<swr_system_font_entry>.size, 88)
        XCTAssertEqual(MemoryLayout<swr_system_fonts>.size, 720)
        XCTAssertEqual(MemoryLayout<swr_system_fonts>.offset(of: \.entries), 16)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v08>.size, 120)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v08>.offset(of: \.system_fonts_size), 112)
        XCTAssertEqual(MemoryLayout<swr_api_v08>.size, 184)
        XCTAssertEqual(MemoryLayout<swr_api_v08>.offset(of: \.font_register), 136)
        XCTAssertEqual(MemoryLayout<swr_api_v08>.offset(of: \.measure_text_v08), 152)
        XCTAssertEqual(MemoryLayout<swr_api_v08>.offset(of: \.system_font_info), 176)
        XCTAssertEqual(SWR_ABI_MINOR, 6, "the legacy constant must not move")
        XCTAssertEqual(SWR_API_V08_FN_COUNT, 22)
        XCTAssertEqual(OpenTypeFeature.kern.tag, 0x6B65726E)
        XCTAssertEqual(OpenTypeFeature.kern.tagString, "kern")
    }

    // MARK: negotiation matrix

    func testNegotiationMatrix() throws {
        func pick(_ b7: Bool, _ a7: Bool, _ b8: Bool, _ a8: Bool, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: b7, hasApiV07: a7, hasBootstrapV08: b8, hasApiV08: a8, minimum: min)
        }
        XCTAssertEqual(try pick(true, true, true, true), .v08, "0.8 bridge on a 0.8 renderer")
        XCTAssertEqual(try pick(true, true, false, false), .v07, "0.8 bridge on a 0.7 renderer falls back to 0.7")
        XCTAssertEqual(try pick(false, false, false, false), .v06, "0.8 bridge on a 0.6 renderer falls back to 0.6")
        XCTAssertThrowsError(try pick(true, true, false, false, .v08)) {
            XCTAssertTrue(String(describing: $0).contains("SWR_STARTUP_ERROR"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.7"))
            XCTAssertTrue(String(describing: $0).contains("requires 0.8"))
        }
        XCTAssertThrowsError(try pick(false, false, false, false, .v07))
        XCTAssertThrowsError(try pick(true, true, true, false), "half-exported 0.8")
        XCTAssertThrowsError(try pick(true, true, false, true), "half-exported 0.8")
        XCTAssertThrowsError(try pick(true, false, false, false), "half-exported 0.7 still refused under the 0.8 policy")
        // the 0.7-only entry point keeps its answer
        XCTAssertEqual(try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, minimum: .v07), .v07)
    }

    func testValidateV08AcceptsTheTrueViewAndRejectsEveryDrift() throws {
        try BridgeNegotiation.validateV08(info08())
        func bad(_ edit: (inout swr_bootstrap_info_v08) -> Void, _ why: String) {
            var i = info08(); edit(&i)
            XCTAssertThrowsError(try BridgeNegotiation.validateV08(i), why)
        }
        bad({ $0.v07.abi_minor = 7 }, "a 0.7 minor is not a 0.8 view")
        bad({ $0.v07.api_table_size = 152 }, "the 0.8 table is 184 bytes")
        bad({ $0.v07.fn_count = 18 }, "22 functions")
        bad({ $0.measure_request_v08_size = 144 }, "request size")
        bad({ $0.measure_result_v08_size += 8 }, "result size")
        bad({ $0.run_face_size = 0 }, "run face size")
        bad({ $0.face_metrics_size -= 4 }, "face metrics size")
        bad({ $0.system_fonts_size += 4 }, "system fonts size")
        bad({ $0.v07.font_info_size = 96 }, "0.7 words are still checked")
        bad({ $0.v07.node_size += 8 }, "0.6 words are still checked")
        bad({ $0.v07.pointer_width = 32 }, "pointer width")
    }

    // MARK: a 0.8 host on a 0.7 renderer: refusal, never silence

    func testExtensionRequestOnA07RendererIsRefused() {
        let b = bridge07()
        XCTAssertFalse(b.supportsTextExtension)
        XCTAssertThrowsError(try b.measure(req(TextExtension(trackingDIP: 1)))) {
            guard case BridgeError.status(let rc, let what) = $0 else { return XCTFail("\($0)") }
            XCTAssertEqual(rc, -15, "SWR_E_UNSUPPORTED")
            XCTAssertTrue(what.contains("no text extension"))
        }
        XCTAssertEqual(v08Calls, 0)
        XCTAssertThrowsError(try b.runFaces(of: TextRunHandle(raw: 1)))
        XCTAssertThrowsError(try b.faceMetrics(family: "Tinos"))
        XCTAssertThrowsError(try b.systemFontInfo())
        // ...while a request without an extension is the 0.6 path and works.
        let m = try? b.measure(req())
        XCTAssertNotNil(m)
        XCTAssertNil(m?.extensionReport)
        XCTAssertEqual(legacyCalls, 1)
    }

    func testNoExtensionAlwaysTakesTheLegacyPathEvenOn08() throws {
        let m = try bridge08().measure(req())
        XCTAssertEqual(legacyCalls, 1)
        XCTAssertEqual(v08Calls, 0, "default behaviour is the 0.6 path: nothing changes for hosts that send no extension")
        XCTAssertNil(m.extensionReport)
    }

    // MARK: marshalling

    func testExtensionMarshalsEveryField() throws {
        var e = TextExtension()
        e.weight = 500
        e.italic = true
        e.width = 87.5
        e.opticalSize = 20
        e.slant = 8
        e.trackingDIP = 1.5
        e.kerningDIP = -0.25
        e.features = [.kern, OpenTypeFeature("tnum", 1), OpenTypeFeature("ss01", 3)]
        e.simulations = .forbidAll
        e.fallbackFamilies = ["Yu Gothic UI", "Segoe UI Emoji"]
        e.baselineOffsetDIP = 15.5
        let m = try bridge08().measure(req(e))
        XCTAssertEqual(v08Calls, 1)
        XCTAssertEqual(legacyCalls, 0)
        let q = seenRequest
        XCTAssertEqual(q.struct_size, 160)
        XCTAssertEqual(q.base.struct_size, 88)
        XCTAssertEqual(q.flags, UInt32(SWR_M08_BASELINE_OFFSET))
        XCTAssertEqual(q.weight_f, 500)
        XCTAssertEqual(q.italic, 1)
        XCTAssertEqual(q.width_axis, 87.5)
        XCTAssertEqual(q.opsz, 20)
        XCTAssertEqual(q.slant, 8)
        XCTAssertEqual(q.tracking_dip, 1.5)
        XCTAssertEqual(q.kerning_dip, -0.25)
        XCTAssertEqual(q.baseline_offset_dip, 15.5)
        XCTAssertEqual(q.simulations, UInt32(SWR_SIM_FORBID_BOLD | SWR_SIM_FORBID_OBLIQUE))
        XCTAssertEqual(q.base.font_weight, 400, "0.6 fields are carried unchanged")
        XCTAssertEqual(q.base.font_size, 18)
        XCTAssertEqual(q.base.text_len, 5)
        XCTAssertEqual(seenFeatures.map { $0.tag }, [0x6B65726E, 0x746E756D, 0x73733031])
        XCTAssertEqual(seenFeatures.map { $0.value }, [1, 1, 3])
        XCTAssertEqual(seenFallbacks, ["Yu Gothic UI", "Segoe UI Emoji"])
        // The report comes back typed, with what was ignored named.
        let r = try XCTUnwrap(m.extensionReport)
        XCTAssertTrue(r.applied.contains(.features) && r.applied.contains(.tracking))
        XCTAssertTrue(r.ignored.contains(.opticalSize) && r.ignored.contains(.weightSnapped))
        XCTAssertEqual(r.resolvedWeight, 600)
        XCTAssertEqual(r.simulations, .bold)
        XCTAssertEqual(m.lines.count, 1)
        XCTAssertEqual(m.firstBaseline, 12)
    }

    func testDefaultExtensionKeepsZeroedFields() throws {
        _ = try bridge08().measure(req(TextExtension(features: [.kern])))
        let q = seenRequest
        XCTAssertEqual(q.flags, 0, "no baseline offset unless asked")
        XCTAssertEqual(q.weight_f, 0, "0 = use font_weight")
        XCTAssertEqual(q.simulations, 0, "0 = the 0.6 behaviour (allow)")
        XCTAssertEqual(q.tracking_dip, 0)
        XCTAssertEqual(q.fallback_count, 0)
        XCTAssertEqual(seenFeatures.count, 1)
    }

    func testLimitsAreRefusedBeforeTheCall() {
        let b = bridge08()
        let many = (0..<17).map { _ in OpenTypeFeature.kern }
        XCTAssertThrowsError(try b.measure(req(TextExtension(features: many)))) {
            guard case BridgeError.status(let rc, _) = $0 else { return XCTFail() }
            XCTAssertEqual(rc, -8)
        }
        XCTAssertNoThrow(try b.measure(req(TextExtension(features: Array(many.prefix(16))))))
        XCTAssertThrowsError(try b.measure(req(TextExtension(fallbackFamilies: (0..<9).map { "F\($0)" })))) {
            guard case BridgeError.status(let rc, _) = $0 else { return XCTFail() }
            XCTAssertEqual(rc, -8)
        }
        XCTAssertThrowsError(try b.measure(req(TextExtension(fallbackFamilies: [""]))))
        XCTAssertThrowsError(try b.measure(req(TextExtension(trackingDIP: .nan))))
        XCTAssertThrowsError(try b.measure(req(TextExtension(weight: 1001))))
    }

    func testRunFacesNamesTheBundledHashAndReportsNotdef() throws {
        let faces = try bridge08().runFaces(of: TextRunHandle(raw: (1 << 32) | 7))
        XCTAssertEqual(faces.count, 2)
        XCTAssertEqual(faces[0].family, "Tinos")
        XCTAssertTrue(faces[0].flags.contains(.primary) && faces[0].flags.contains(.bundled))
        XCTAssertEqual(faces[0].sha256Hex, (0..<32).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(faces[0].notdefCount, 0)
        XCTAssertEqual(faces[0].postScriptName, "Tinos-Regular")
        XCTAssertTrue(faces[1].flags.contains(.fallback) && faces[1].flags.contains(.unresolved))
        XCTAssertEqual(faces[1].notdefCount, 1, "negative control: an unmapped code point reports .notdef")
        XCTAssertEqual(faces[1].sha256, [UInt8](repeating: 0, count: 32))
    }

    func testFaceMetricsAndSystemInfoDecode() throws {
        let b = bridge08()
        let m = try b.faceMetrics(family: "Tinos")
        XCTAssertTrue(m.found && m.bundled)
        XCTAssertEqual(m.source, .bundled)
        XCTAssertEqual(m.unitsPerEm, 2048)
        XCTAssertEqual(m.hheaAscent, 1825)
        XCTAssertEqual(m.hheaDescent, -443)
        XCTAssertEqual(m.hheaAscent(pointSize: 18), 16.040039, accuracy: 1e-4)
        XCTAssertEqual(m.axes, [AxisRange(tag: "wght", minValue: 300, maxValue: 700, defaultValue: 400)])
        XCTAssertEqual(m.family, "Tinos")
        XCTAssertFalse(try b.faceMetrics(family: "NoSuchFamily").found)
        let s = try b.systemFontInfo()
        XCTAssertTrue(s.segoeUI && s.sitka && !s.segoeUIVariable && !s.cascadiaMono)
        XCTAssertEqual(s.familyCount, 321)
        XCTAssertEqual(s.entries.count, 8)
        XCTAssertEqual(s.entries[0], SystemFontEntry(name: "Segoe UI", version: "Version 1.23", present: true, faceCount: 12))
        XCTAssertFalse(s.entries[1].present)
    }

    func testFixedCStringHelpersTruncateAndTerminate() {
        var f = swr_run_face()
        setCString(&f.version, String(repeating: "x", count: 100))
        XCTAssertEqual(cString(&f.version).count, 31, "NUL always fits")
        setCString(&f.version, "")
        XCTAssertEqual(cString(&f.version), "")
    }
}
