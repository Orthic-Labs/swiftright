import CSwiftRight
import Foundation

// ABI revision negotiation (platform neutral, so it is unit-tested on every host).
//
// 0.7 is ADDITIVE (swiftright.h, "REVISION 0.7"). A 0.7 renderer still answers the legacy
// `swr_bootstrap_query` / `swr_get_api` exactly as a 0.6 renderer does (minor 6, 88 / 136
// bytes), so a 0.6 bridge keeps working on it. It also exports `swr_bootstrap_query_v07` and
// `swr_get_api_v07`; this bridge prefers them when both are present. A 0.6 renderer has
// neither, so a 0.7 bridge falls back to the 0.6 view unless the host demanded 0.7.

public enum BridgeRevision: Int, Comparable, CustomStringConvertible {
    case v06 = 6
    case v07 = 7
    public static func < (a: BridgeRevision, b: BridgeRevision) -> Bool { a.rawValue < b.rawValue }
    public var description: String { "0.\(rawValue)" }
}

public enum BridgeNegotiation {
    /// Picks the view to use from the exports the renderer has. Pure policy.
    /// - Both 0.7 exports present: 0.7. Neither: 0.6 (or refusal when `minimum` is 0.7).
    /// - Exactly one: a half-exported renderer is refused, never guessed at.
    public static func choose(hasBootstrapV07: Bool, hasApiV07: Bool, minimum: BridgeRevision) throws -> BridgeRevision {
        switch (hasBootstrapV07, hasApiV07) {
        case (true, true):
            return .v07
        case (false, false):
            if minimum > .v06 {
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI 0.6 (no swr_bootstrap_query_v07), host requires \(minimum)")
            }
            return .v06
        case (true, false):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api_v07 (swr_bootstrap_query_v07 present)")
        case (false, true):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query_v07 (swr_get_api_v07 present)")
        }
    }

    /// The 0.6-shaped identity of a 0.7 bootstrap (what `Bridge.info` publishes). Values are the
    /// renderer's own: abi_minor 7, the 152-byte table and 18 functions.
    public static func baseView(of i: swr_bootstrap_info_v07) -> swr_bootstrap_info {
        var b = swr_bootstrap_info()
        b.struct_size = i.struct_size
        b.abi_major = i.abi_major
        b.abi_minor = i.abi_minor
        b.pointer_width = i.pointer_width
        b.arch = i.arch
        b.host_callbacks_size = i.host_callbacks_size
        b.api_table_size = i.api_table_size
        b.transaction_size = i.transaction_size
        b.node_size = i.node_size
        b.primitive_size = i.primitive_size
        b.semantic_size = i.semantic_size
        b.ax_text_run_size = i.ax_text_run_size
        b.event_size = i.event_size
        b.measure_request_size = i.measure_request_size
        b.measure_result_size = i.measure_result_size
        b.line_info_size = i.line_info_size
        b.char_cell_size = i.char_cell_size
        b.fn_count = i.fn_count
        b.stats_size = i.stats_size
        return b
    }

    /// Validates the 0.7 view BEFORE the 0.7 table is requested: minor 7, every size, the 152-byte
    /// table, 18 functions and the two font size words.
    public static func validateV07(_ i: swr_bootstrap_info_v07) throws {
        let base = baseView(of: i)
        try Bridge.validateIdentity(base,
                                    minor: UInt32(SWR_ABI_MINOR_V07),
                                    apiTableSize: MemoryLayout<swr_api_v07>.size,
                                    fnCount: UInt32(SWR_API_V07_FN_COUNT))
        let extra: [(String, UInt32, Int)] = [
            ("font_info", i.font_info_size, MemoryLayout<swr_font_info>.size),
            ("font_resolution", i.font_resolution_size, MemoryLayout<swr_font_resolution>.size),
        ]
        for (name, got, want) in extra where Int(got) != want {
            throw BridgeError.startup("SWR_STARTUP_ERROR: \(name) table size mismatch expected \(want) got \(got)")
        }
    }

    /// A 0.7 table viewed as the 0.6 table the rest of the bridge uses (same 16 functions).
    public static func baseTable(of t: swr_api_v07) -> swr_api {
        var a = swr_api()
        a.struct_size = UInt32(MemoryLayout<swr_api>.size)
        a.reserved = 0
        a.run = t.run
        a.request_quit = t.request_quit
        a.window_request_close = t.window_request_close
        a.window_get_metrics = t.window_get_metrics
        a.commit = t.commit
        a.measure_text = t.measure_text
        a.text_run_cells = t.text_run_cells
        a.text_run_release = t.text_run_release
        a.event_pop = t.event_pop
        a.request_ticks = t.request_ticks
        a.request_modal = t.request_modal
        a.selftest_reentry = t.selftest_reentry
        a.get_stats = t.get_stats
        a.shutdown_complete = t.shutdown_complete
        a.image_register = t.image_register
        a.image_release = t.image_release
        return a
    }
}
