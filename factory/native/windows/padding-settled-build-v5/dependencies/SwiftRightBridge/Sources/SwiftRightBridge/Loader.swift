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
    static func load(path: String? = nil) throws -> Bridge {
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
    static func load(path: String? = nil) throws -> Bridge {
        throw BridgeError.unsupportedPlatform
    }
    #endif
}
