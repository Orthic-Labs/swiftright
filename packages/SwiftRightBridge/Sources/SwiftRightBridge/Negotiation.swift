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
    case v08 = 8
    case v09 = 9
    case v10 = 10
    case v11 = 11
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

    /// 0.8 negotiation (additive over `choose`). The 0.8 exports are looked at first:
    /// - both present: 0.8 (the renderer also exports the 0.7 and 0.6 views, which a 0.7 or 0.6 host uses);
    /// - exactly one: a half-exported renderer is refused, never guessed at;
    /// - neither: the 0.7/0.6 decision of `choose` applies, and a host that demands 0.8 (`minimum`) is refused with a typed
    ///   diagnostic (a 0.8 bridge on a 0.7 renderer: fall back with the text extension unavailable, or refuse; never silent).
    public static func choose(hasBootstrapV07: Bool, hasApiV07: Bool, hasBootstrapV08: Bool, hasApiV08: Bool,
                              minimum: BridgeRevision) throws -> BridgeRevision {
        switch (hasBootstrapV08, hasApiV08) {
        case (true, true):
            return .v08
        case (true, false):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api_v08 (swr_bootstrap_query_v08 present)")
        case (false, true):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query_v08 (swr_get_api_v08 present)")
        case (false, false):
            let lower = try choose(hasBootstrapV07: hasBootstrapV07, hasApiV07: hasApiV07, minimum: min(minimum, .v07))
            if minimum > lower {
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI \(lower) (no swr_bootstrap_query_v08), host requires \(minimum)")
            }
            return lower
        }
    }

    /// 0.9 negotiation (additive over the 0.8 `choose`): both 0.9 exports present: 0.9; exactly one: refused; neither: the 0.8
    /// decision applies (a host that demands 0.9 is refused with a typed diagnostic).
    public static func choose(hasBootstrapV07: Bool, hasApiV07: Bool, hasBootstrapV08: Bool, hasApiV08: Bool,
                              hasBootstrapV09: Bool, hasApiV09: Bool, minimum: BridgeRevision) throws -> BridgeRevision {
        switch (hasBootstrapV09, hasApiV09) {
        case (true, true):
            return .v09
        case (true, false):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api_v09 (swr_bootstrap_query_v09 present)")
        case (false, true):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query_v09 (swr_get_api_v09 present)")
        case (false, false):
            let lower = try choose(hasBootstrapV07: hasBootstrapV07, hasApiV07: hasApiV07, hasBootstrapV08: hasBootstrapV08,
                                   hasApiV08: hasApiV08, minimum: min(minimum, .v08))
            if minimum > lower {
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI \(lower) (no swr_bootstrap_query_v09), host requires \(minimum)")
            }
            return lower
        }
    }

    /// 0.10 negotiation (additive over the 0.9 `choose`): both 0.10 exports present: 0.10; exactly one: refused; neither: the 0.9
    /// decision applies (a host that demands 0.10 is refused with a typed diagnostic).
    public static func choose(hasBootstrapV07: Bool, hasApiV07: Bool, hasBootstrapV08: Bool, hasApiV08: Bool,
                              hasBootstrapV09: Bool, hasApiV09: Bool, hasBootstrapV10: Bool, hasApiV10: Bool,
                              minimum: BridgeRevision) throws -> BridgeRevision {
        switch (hasBootstrapV10, hasApiV10) {
        case (true, true):
            return .v10
        case (true, false):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api_v10 (swr_bootstrap_query_v10 present)")
        case (false, true):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query_v10 (swr_get_api_v10 present)")
        case (false, false):
            let lower = try choose(hasBootstrapV07: hasBootstrapV07, hasApiV07: hasApiV07, hasBootstrapV08: hasBootstrapV08,
                                   hasApiV08: hasApiV08, hasBootstrapV09: hasBootstrapV09, hasApiV09: hasApiV09,
                                   minimum: min(minimum, .v09))
            if minimum > lower {
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI \(lower) (no swr_bootstrap_query_v10), host requires \(minimum)")
            }
            return lower
        }
    }

    /// 0.11 negotiation (additive over the 0.10 `choose`): both 0.11 exports present: 0.11; exactly one: refused; neither: the 0.10
    /// decision applies (a host that demands 0.11 is refused with a typed diagnostic).
    public static func choose(hasBootstrapV07: Bool, hasApiV07: Bool, hasBootstrapV08: Bool, hasApiV08: Bool,
                              hasBootstrapV09: Bool, hasApiV09: Bool, hasBootstrapV10: Bool, hasApiV10: Bool,
                              hasBootstrapV11: Bool, hasApiV11: Bool, minimum: BridgeRevision) throws -> BridgeRevision {
        switch (hasBootstrapV11, hasApiV11) {
        case (true, true):
            return .v11
        case (true, false):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api_v11 (swr_bootstrap_query_v11 present)")
        case (false, true):
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query_v11 (swr_get_api_v11 present)")
        case (false, false):
            let lower = try choose(hasBootstrapV07: hasBootstrapV07, hasApiV07: hasApiV07, hasBootstrapV08: hasBootstrapV08,
                                   hasApiV08: hasApiV08, hasBootstrapV09: hasBootstrapV09, hasApiV09: hasApiV09,
                                   hasBootstrapV10: hasBootstrapV10, hasApiV10: hasApiV10, minimum: min(minimum, .v10))
            if minimum > lower {
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI \(lower) (no swr_bootstrap_query_v11), host requires \(minimum)")
            }
            return lower
        }
    }

    /// Validates the 0.11 view BEFORE the table is requested: minor 11, every 0.10 size, and the wheel delta word.
    public static func validateV11(_ i: swr_bootstrap_info_v11) throws {
        try validateV10(i.v10, minor: UInt32(SWR_ABI_MINOR_V11))
        if Int(i.wheel_delta) != Int(SWR_WHEEL_DELTA) {
            throw BridgeError.startup("SWR_STARTUP_ERROR: wheel delta mismatch expected \(SWR_WHEEL_DELTA) got \(i.wheel_delta)")
        }
    }

    /// Validates the 0.10 view BEFORE the table is requested: minor 10, every 0.9 size, and the run options size word.
    public static func validateV10(_ i: swr_bootstrap_info_v10) throws { try validateV10(i, minor: UInt32(SWR_ABI_MINOR_V10)) }

    static func validateV10(_ i: swr_bootstrap_info_v10, minor: UInt32) throws {
        try validateV09(i.v09, minor: minor)
        let got = i.run_options_v10_size, want = MemoryLayout<swr_run_options_v10>.size
        if Int(got) != want {
            throw BridgeError.startup("SWR_STARTUP_ERROR: run_options_v10 table size mismatch expected \(want) got \(got)")
        }
    }

    /// Validates the 0.9 view BEFORE the table is requested: minor 9, every 0.6 size, the 184-byte 0.8 table, 22 functions, the
    /// 0.7 and 0.8 size words and the two 0.9 size words.
    public static func validateV09(_ i: swr_bootstrap_info_v09) throws { try validateV09(i, minor: UInt32(SWR_ABI_MINOR_V09)) }

    static func validateV09(_ i: swr_bootstrap_info_v09, minor: UInt32) throws {
        try validateV08(i.v08, minor: minor)
        let extra: [(String, UInt32, Int)] = [
            ("range_entry", i.range_entry_size, MemoryLayout<swr_range_entry>.size),
            ("transaction_v09", i.transaction_v09_size, MemoryLayout<swr_transaction_v09>.size),
        ]
        for (name, got, want) in extra where Int(got) != want {
            throw BridgeError.startup("SWR_STARTUP_ERROR: \(name) table size mismatch expected \(want) got \(got)")
        }
    }

    /// The 0.7 view contained in a 0.8 bootstrap.
    public static func v07View(of i: swr_bootstrap_info_v08) -> swr_bootstrap_info_v07 { i.v07 }

    /// Validates the 0.8 view BEFORE the 0.8 table is requested: minor 8, every 0.6 size, the 184-byte table, 22 functions,
    /// the two 0.7 font size words and the five 0.8 struct sizes.
    public static func validateV08(_ i: swr_bootstrap_info_v08) throws { try validateV08(i, minor: UInt32(SWR_ABI_MINOR_V08)) }

    static func validateV08(_ i: swr_bootstrap_info_v08, minor: UInt32) throws {
        let base = baseView(of: i.v07)
        try Bridge.validateIdentity(base,
                                    minor: minor,
                                    apiTableSize: MemoryLayout<swr_api_v08>.size,
                                    fnCount: UInt32(SWR_API_V08_FN_COUNT))
        let extra: [(String, UInt32, Int)] = [
            ("font_info", i.v07.font_info_size, MemoryLayout<swr_font_info>.size),
            ("font_resolution", i.v07.font_resolution_size, MemoryLayout<swr_font_resolution>.size),
            ("measure_request_v08", i.measure_request_v08_size, MemoryLayout<swr_measure_request_v08>.size),
            ("measure_result_v08", i.measure_result_v08_size, MemoryLayout<swr_measure_result_v08>.size),
            ("run_face", i.run_face_size, MemoryLayout<swr_run_face>.size),
            ("face_metrics", i.face_metrics_size, MemoryLayout<swr_face_metrics>.size),
            ("system_fonts", i.system_fonts_size, MemoryLayout<swr_system_fonts>.size),
        ]
        for (name, got, want) in extra where Int(got) != want {
            throw BridgeError.startup("SWR_STARTUP_ERROR: \(name) table size mismatch expected \(want) got \(got)")
        }
    }

    /// A 0.8 table viewed as the 0.7 table (same 18 functions).
    public static func v07Table(of t: swr_api_v08) -> swr_api_v07 {
        var a = swr_api_v07()
        a.struct_size = UInt32(MemoryLayout<swr_api_v07>.size)
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
        a.font_register = t.font_register
        a.font_resolve = t.font_resolve
        return a
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
