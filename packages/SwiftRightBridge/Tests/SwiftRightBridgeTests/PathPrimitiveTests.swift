import XCTest
@testable import SwiftRightBridge
import CSwiftRight

// ABI 0.12 (issue #52): path primitive and path clip. Layout, negotiation, validation, the path table on the wire and the
// primitive encoding. The renderer side (table decoding, validation, row-band cover, GPUI painting) is covered by
// render/swiftright-render src/paths.rs tests, src/tree.rs `path_prim_*` / `clip_push_with_image_id_*` and src/lib.rs
// `bootstrap_v12_extends_v11_and_reports_minor_12`.

nonisolated(unsafe) private var seenStructSize: UInt32 = 0
nonisolated(unsafe) private var seenEntries: [swr_path_entry] = []
nonisolated(unsafe) private var seenCmds: [UInt8] = []
nonisolated(unsafe) private var seenPts: [Float] = []
nonisolated(unsafe) private var seenPrims: [swr_primitive] = []

private func fakeCommit(_ t: UnsafePointer<swr_transaction>?) -> Int32 {
    guard let t else { return -1 }
    seenStructSize = t.pointee.struct_size
    seenEntries = []; seenCmds = []; seenPts = []
    seenPrims = t.pointee.primitives.map { Array(UnsafeBufferPointer(start: $0, count: Int(t.pointee.primitive_count))) } ?? []
    if Int(t.pointee.struct_size) >= MemoryLayout<swr_transaction_v12>.size {
        t.withMemoryRebound(to: swr_transaction_v12.self, capacity: 1) { p in
            if let e = p.pointee.paths { seenEntries = Array(UnsafeBufferPointer(start: e, count: Int(p.pointee.path_count))) }
            if let c = p.pointee.path_cmds { seenCmds = Array(UnsafeBufferPointer(start: c, count: Int(p.pointee.path_cmd_total))) }
            if let q = p.pointee.path_pts { seenPts = Array(UnsafeBufferPointer(start: q, count: Int(p.pointee.path_pt_total) * 2)) }
        }
    }
    return 0
}

final class PathPrimitiveTests: XCTestCase {
    private let square = PathSpec(commands: [.move(0, 0), .line(10, 0), .line(10, 10), .line(0, 10), .close])
    private let curve = PathSpec(commands: [.move(0, 0), .quad(5, 5, 10, 0), .cubic(1, 2, 3, 4, 5, 6), .close],
                                 evenOdd: true, cap: .round, join: .bevel, miterLimit: 2.5)

    func testLayoutMatchesTheHeader() {
        XCTAssertEqual(MemoryLayout<swr_path_entry>.size, 32)
        XCTAssertEqual(MemoryLayout<swr_transaction_v12>.size, 128)
        XCTAssertEqual(MemoryLayout<swr_transaction_v12>.offset(of: \.paths), 88)
        XCTAssertEqual(MemoryLayout<swr_transaction_v12>.offset(of: \.path_count), 112)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v12>.size, 152)
        XCTAssertEqual(MemoryLayout<swr_bootstrap_info_v12>.offset(of: \.path_entry_size), 144)
        XCTAssertEqual(MemoryLayout<swr_primitive>.size, 80, "the primitive does not grow")
        XCTAssertEqual(SWR_ABI_MINOR_V12, 12)
        XCTAssertEqual(SWR_ABI_MINOR_V11, 11, "the 0.11 constant must not move")
        XCTAssertEqual(SWR_PRIM_PATH, 4)
        XCTAssertEqual([SWR_PATH_MOVE, SWR_PATH_LINE, SWR_PATH_QUAD, SWR_PATH_CUBIC, SWR_PATH_CLOSE], [0, 1, 2, 3, 4])
        XCTAssertEqual(SWR_PATH_EVEN_ODD, 1)
        XCTAssertEqual(BridgeRevision.v12.rawValue, 12)
        XCTAssertEqual(BridgeRevision.v12.description, "0.12")
    }

    private func bridge(_ revision: BridgeRevision) -> Bridge {
        var api = swr_api(); api.commit = fakeCommit
        var info = swr_bootstrap_info(); info.abi_minor = UInt32(revision.rawValue)
        return Bridge(api: api, info: info, revision: revision)
    }

    func testSupportFollowsTheRevision() {
        XCTAssertFalse(bridge(.v11).supportsPaths)
        XCTAssertTrue(bridge(.v12).supportsPaths)
        XCTAssertTrue(bridge(.v12).supportsPointerWheel, "0.12 keeps 0.11 behaviour")
    }

    func testNegotiationMatrix() throws {
        func pick(_ b12: Bool, _ a12: Bool, _ b11: Bool = true, _ a11: Bool = true, _ min: BridgeRevision = .v06) throws -> BridgeRevision {
            try BridgeNegotiation.choose(hasBootstrapV07: true, hasApiV07: true, hasBootstrapV08: true, hasApiV08: true,
                                         hasBootstrapV09: true, hasApiV09: true, hasBootstrapV10: true, hasApiV10: true,
                                         hasBootstrapV11: b11, hasApiV11: a11, hasBootstrapV12: b12, hasApiV12: a12, minimum: min)
        }
        XCTAssertEqual(try pick(true, true), .v12)
        XCTAssertEqual(try pick(false, false), .v11, "a 0.12 bridge on a 0.11 renderer falls back")
        XCTAssertEqual(try pick(false, false, false, false), .v10)
        XCTAssertThrowsError(try pick(true, false), "half-exported 0.12")
        XCTAssertThrowsError(try pick(false, true), "half-exported 0.12")
        XCTAssertThrowsError(try pick(false, false, true, true, .v12)) {
            XCTAssertTrue(String(describing: $0).contains("requires 0.12"))
            XCTAssertTrue(String(describing: $0).contains("ABI 0.11"))
        }
    }

    private func info12() -> swr_bootstrap_info_v12 {
        var v = swr_bootstrap_info_v12()
        var base = v.v11.v10.v09.v08.v07
        base.api_table_size = UInt32(MemoryLayout<swr_api_v08>.size)
        base.fn_count = UInt32(SWR_API_V08_FN_COUNT)
        base.abi_major = UInt32(SWR_ABI_MAJOR)
        base.abi_minor = UInt32(SWR_ABI_MINOR_V12)
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
        v.v11.v10.v09.v08.v07 = base
        v.v11.v10.v09.v08.measure_request_v08_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        v.v11.v10.v09.v08.measure_result_v08_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
        v.v11.v10.v09.v08.run_face_size = UInt32(MemoryLayout<swr_run_face>.size)
        v.v11.v10.v09.v08.face_metrics_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        v.v11.v10.v09.v08.system_fonts_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        v.v11.v10.v09.range_entry_size = UInt32(MemoryLayout<swr_range_entry>.size)
        v.v11.v10.v09.transaction_v09_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
        v.v11.v10.run_options_v10_size = UInt32(MemoryLayout<swr_run_options_v10>.size)
        v.v11.wheel_delta = UInt32(SWR_WHEEL_DELTA)
        v.path_entry_size = UInt32(MemoryLayout<swr_path_entry>.size)
        v.transaction_v12_size = UInt32(MemoryLayout<swr_transaction_v12>.size)
        return v
    }

    func testValidateV12() throws {
        #if arch(x86_64)
        try BridgeNegotiation.validateV12(info12())
        #endif
        var a = info12(); a.v11.v10.v09.v08.v07.abi_minor = UInt32(SWR_ABI_MINOR_V11)
        XCTAssertThrowsError(try BridgeNegotiation.validateV12(a), "a 0.11 minor is not a 0.12 view")
        var b = info12(); b.path_entry_size = 28
        XCTAssertThrowsError(try BridgeNegotiation.validateV12(b))
        var c = info12(); c.transaction_v12_size = 88
        XCTAssertThrowsError(try BridgeNegotiation.validateV12(c))
        var d = info12(); d.v11.wheel_delta = 60
        XCTAssertThrowsError(try BridgeNegotiation.validateV12(d))
    }

    func testPathTableEncodesCommandsPointsFlagsAndDeduplicates() {
        let table = PathTable()
        XCTAssertEqual(table.add(square), 0)
        XCTAssertEqual(table.add(curve), 1)
        XCTAssertEqual(table.add(square), 0, "an equal spec shares its entry")
        XCTAssertEqual(table.entries.count, 2)
        XCTAssertEqual(table.commands, [0, 1, 1, 1, 4, 0, 2, 3, 4])
        XCTAssertEqual(table.points.count, 2 * (4 + 1 + 2 + 3))
        let a = table.entries[0], b = table.entries[1]
        XCTAssertEqual([a.cmd_offset, a.cmd_count, a.pt_offset, a.pt_count, a.flags], [0, 5, 0, 4, 0])
        XCTAssertEqual(a.miter_limit, 0)
        XCTAssertEqual([b.cmd_offset, b.cmd_count, b.pt_offset, b.pt_count], [5, 4, 4, 6])
        XCTAssertEqual(b.flags, 1 | (1 << 1) | (2 << 3))
        XCTAssertEqual(b.miter_limit, 2.5)
        XCTAssertEqual(Array(table.points[8..<12]), [0, 0, 5, 5], "pt_offset counts points, so the second path starts at float 8")
    }

    func testPrimitiveEncoding() {
        let table = PathTable()
        let p = cPrimitive(.pathShape(square, fill: 0xFF0000FF, strokeColor: 0x00FF00FF, strokeWidth: 2), table: table)
        XCTAssertEqual(p.kind, 4)
        XCTAssertEqual(p.color, 0xFF0000FF)
        XCTAssertEqual(p.border_color, 0x00FF00FF)
        XCTAssertEqual(p.border_width, 2)
        XCTAssertEqual(p.image_id, 0)
        let c = cPrimitive(.clipPath(Rect(x: 1, y: 2, w: 3, h: 4), curve), table: table)
        XCTAssertEqual(c.kind, 5)
        XCTAssertEqual(c.image_id, 2, "image_id = 1 + the table index (0 means a plain rect clip)")
        XCTAssertEqual([c.rect.x, c.rect.y, c.rect.w, c.rect.h], [1, 2, 3, 4])
        let plain = cPrimitive(.clipPush(Rect(x: 1, y: 2, w: 3, h: 4)), table: table)
        XCTAssertEqual(plain.image_id, 0)
        XCTAssertEqual(cPrimitive(.pathShape(square, fill: 1)).image_id, UInt32.max, "no table: an index the renderer refuses")
    }

    private func pathTx() -> Transaction {
        Transaction(version: 1, upserts: [NodeUpsert(id: 1, bounds: Rect(x: 0, y: 0, w: 10, h: 10), primitives: [
            .clipPath(Rect(x: 0, y: 0, w: 10, h: 10), curve),
            .pathShape(square, fill: 0xFF0000FF),
            .clipPop,
        ])])
    }

    func testCommitCarriesThePathTableOn012() throws {
        seenStructSize = 0
        let b = bridge(.v12)
        try BridgeWindow.makeForTesting(bridge: b, handle: 1).commit(pathTx())
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction_v12>.size)
        XCTAssertEqual(seenEntries.count, 2)
        XCTAssertEqual(seenCmds.count, 9)
        XCTAssertEqual(seenPts.count, 2 * 10)
        XCTAssertEqual(seenPrims.map(\.kind), [5, 4, 6])
        XCTAssertEqual(seenPrims[0].image_id, 1)
        XCTAssertEqual(seenPrims[1].image_id, 1, "the square is entry 1 (the clip's curve was added first as entry 0)")
    }

    func testCommitIsTheOldShapeBefore012() throws {
        seenStructSize = 0
        let b = bridge(.v11)
        try BridgeWindow.makeForTesting(bridge: b, handle: 1).commit(Transaction(version: 1, upserts: [
            NodeUpsert(id: 1, bounds: Rect(x: 0, y: 0, w: 10, h: 10), primitives: [.rect(Rect(x: 0, y: 0, w: 5, h: 5), color: 1)])]))
        XCTAssertEqual(Int(seenStructSize), MemoryLayout<swr_transaction_v09>.size, "a 0.11 renderer gets the 88-byte transaction")
        XCTAssertTrue(seenEntries.isEmpty)
    }
}
