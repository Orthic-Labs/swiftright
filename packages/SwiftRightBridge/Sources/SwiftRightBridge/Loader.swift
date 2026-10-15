import CSwiftRight
import Foundation
#if os(Windows)
import WinSDK
#endif

// Explicit renderer loading. The renderer is never bound through the import table:
// a missing/incompatible DLL yields a typed `SWR_STARTUP_ERROR:` diagnostic instead of
// the loader killing the process (bridge-faults finding 1).

public extension Bridge {
    /// Environment variable that overrides the renderer path.
    static let rendererPathVariable = "SWIFTRIGHT_RENDER_DLL"

    #if os(Windows)
    /// Loads `swiftright_render.dll` (or `path`, or $SWIFTRIGHT_RENDER_DLL), calls ONLY
    /// `swr_bootstrap_query`, validates ABI identity, and only then resolves the function
    /// table. Throws `BridgeError.startup` with a deterministic message on any mismatch.
    static func load(path: String? = nil, minimumRevision: BridgeRevision = .v06) throws -> Bridge {
        let chosen = path
            ?? ProcessInfo.processInfo.environment[rendererPathVariable]
            ?? "swiftright_render.dll"
        let handle: HMODULE? = chosen.withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        guard let module = handle else {
            let err = GetLastError()
            switch err {
            case 2, 3, 126:
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer not found \(chosen)")
            case 127:
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer load failed \(chosen) (win32 error 127, procedure not found; the host must embed the ComCtl v6 manifest dependency: comctl32 TaskDialogIndirect)")
            case 193:
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer load failed \(chosen) (win32 error 193, wrong architecture)")
            default:
                throw BridgeError.startup("SWR_STARTUP_ERROR: renderer load failed \(chosen) (win32 error \(err))")
            }
        }

        typealias BootstrapFn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info>?, UInt32) -> Int32
        typealias GetAPIFn = @convention(c) (UnsafeMutablePointer<swr_api>?, UInt32) -> Int32

        // ABI 0.7 is additive: prefer the versioned exports when the renderer has them, else use the 0.6 view
        // (a 0.6 renderer, or a 0.7 renderer asked for the legacy view) unless the host demanded 0.7.
        let bootV07Raw = GetProcAddress(module, "swr_bootstrap_query_v07")
        let apiV07Raw = GetProcAddress(module, "swr_get_api_v07")
        let bootV08Raw = GetProcAddress(module, "swr_bootstrap_query_v08")
        let apiV08Raw = GetProcAddress(module, "swr_get_api_v08")
        let bootV09Raw = GetProcAddress(module, "swr_bootstrap_query_v09")
        let apiV09Raw = GetProcAddress(module, "swr_get_api_v09")
        let revision = try BridgeNegotiation.choose(hasBootstrapV07: bootV07Raw != nil, hasApiV07: apiV07Raw != nil,
                                                    hasBootstrapV08: bootV08Raw != nil, hasApiV08: apiV08Raw != nil,
                                                    hasBootstrapV09: bootV09Raw != nil, hasApiV09: apiV09Raw != nil,
                                                    minimum: minimumRevision)
        if revision == .v09 || revision == .v08, let bootV08Raw = (revision == .v09 ? bootV09Raw : bootV08Raw),
           let apiV08Raw = (revision == .v09 ? apiV09Raw : apiV08Raw) {
            typealias BootstrapV08Fn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info_v08>?, UInt32) -> Int32
            typealias BootstrapV09Fn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info_v09>?, UInt32) -> Int32
            typealias GetAPIV08Fn = @convention(c) (UnsafeMutablePointer<swr_api_v08>?, UInt32) -> Int32
            var info8 = swr_bootstrap_info_v08()
            if revision == .v09 {
                let boot9 = unsafeBitCast(bootV08Raw, to: BootstrapV09Fn.self)
                var info9 = swr_bootstrap_info_v09()
                let rc9 = withUnsafeMutablePointer(to: &info9) { boot9($0, UInt32(MemoryLayout<swr_bootstrap_info_v09>.size)) }
                if rc9 != 0 {
                    throw BridgeError.startup("SWR_STARTUP_ERROR: bootstrap query v09 rejected rc=\(rc9)")
                }
                try BridgeNegotiation.validateV09(info9)
                info8 = info9.v08
            } else {
                let boot8 = unsafeBitCast(bootV08Raw, to: BootstrapV08Fn.self)
                let rc7 = withUnsafeMutablePointer(to: &info8) { boot8($0, UInt32(MemoryLayout<swr_bootstrap_info_v08>.size)) }
                if rc7 != 0 {
                    throw BridgeError.startup("SWR_STARTUP_ERROR: bootstrap query v08 rejected rc=\(rc7)")
                }
                try BridgeNegotiation.validateV08(info8)
            }
            let getAPI8 = unsafeBitCast(apiV08Raw, to: GetAPIV08Fn.self)
            var api8 = swr_api_v08()
            let rc8 = withUnsafeMutablePointer(to: &api8) { getAPI8($0, UInt32(MemoryLayout<swr_api_v08>.size)) }
            if rc8 != 0 {
                throw BridgeError.startup("SWR_STARTUP_ERROR: function table v08 rejected rc=\(rc8)")
            }
            guard let fontRegister = api8.font_register, let fontResolve = api8.font_resolve,
                  let measure8 = api8.measure_text_v08, let runFaces = api8.text_run_faces,
                  let faceMetrics = api8.font_face_metrics, let sysInfo = api8.system_font_info else {
                throw BridgeError.startup("SWR_STARTUP_ERROR: 0.8 function table has a null entry")
            }
            return Bridge(api: BridgeNegotiation.baseTable(of: BridgeNegotiation.v07Table(of: api8)),
                          info: BridgeNegotiation.baseView(of: info8.v07), revision: revision,
                          fonts: FontEntryPoints(register: fontRegister, resolve: fontResolve),
                          textExtension: TextExtensionEntryPoints(measure: measure8, runFaces: runFaces,
                                                                  faceMetrics: faceMetrics, systemFontInfo: sysInfo))
        }
        if revision == .v07, let bootV07Raw, let apiV07Raw {
            typealias BootstrapV07Fn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info_v07>?, UInt32) -> Int32
            typealias GetAPIV07Fn = @convention(c) (UnsafeMutablePointer<swr_api_v07>?, UInt32) -> Int32
            let boot7 = unsafeBitCast(bootV07Raw, to: BootstrapV07Fn.self)
            var info7 = swr_bootstrap_info_v07()
            let rc7 = withUnsafeMutablePointer(to: &info7) { boot7($0, UInt32(MemoryLayout<swr_bootstrap_info_v07>.size)) }
            if rc7 != 0 {
                throw BridgeError.startup("SWR_STARTUP_ERROR: bootstrap query v07 rejected rc=\(rc7)")
            }
            try BridgeNegotiation.validateV07(info7)
            let getAPI7 = unsafeBitCast(apiV07Raw, to: GetAPIV07Fn.self)
            var api7 = swr_api_v07()
            let rc8 = withUnsafeMutablePointer(to: &api7) { getAPI7($0, UInt32(MemoryLayout<swr_api_v07>.size)) }
            if rc8 != 0 {
                throw BridgeError.startup("SWR_STARTUP_ERROR: function table v07 rejected rc=\(rc8)")
            }
            guard let fontRegister = api7.font_register, let fontResolve = api7.font_resolve else {
                throw BridgeError.startup("SWR_STARTUP_ERROR: 0.7 function table has no font entries")
            }
            return Bridge(api: BridgeNegotiation.baseTable(of: api7), info: BridgeNegotiation.baseView(of: info7),
                          revision: .v07, fonts: FontEntryPoints(register: fontRegister, resolve: fontResolve))
        }

        guard let bootRaw = GetProcAddress(module, "swr_bootstrap_query") else {
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query")
        }
        let boot = unsafeBitCast(bootRaw, to: BootstrapFn.self)
        var info = swr_bootstrap_info()
        let rc = withUnsafeMutablePointer(to: &info) { boot($0, UInt32(MemoryLayout<swr_bootstrap_info>.size)) }
        if rc != 0 {
            throw BridgeError.startup("SWR_STARTUP_ERROR: bootstrap query rejected rc=\(rc)")
        }
        try Bridge.validate(info)

        guard let apiRaw = GetProcAddress(module, "swr_get_api") else {
            throw BridgeError.startup("SWR_STARTUP_ERROR: missing symbol swr_get_api")
        }
        let getAPI = unsafeBitCast(apiRaw, to: GetAPIFn.self)
        var api = swr_api()
        let rc2 = withUnsafeMutablePointer(to: &api) { getAPI($0, UInt32(MemoryLayout<swr_api>.size)) }
        if rc2 != 0 {
            throw BridgeError.startup("SWR_STARTUP_ERROR: function table rejected rc=\(rc2)")
        }
        return Bridge(api: api, info: info)
    }
    #else
    static func load(path: String? = nil, minimumRevision: BridgeRevision = .v06) throws -> Bridge {
        throw BridgeError.unsupportedPlatform
    }
    #endif
}
