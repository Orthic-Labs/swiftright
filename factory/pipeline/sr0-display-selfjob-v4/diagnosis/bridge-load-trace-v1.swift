// Additive Windows host trace. Keep Bridge/renderer/runtime sources unchanged.
// Paste helper plus exact call-site markers into fresh diagnostic host only.
import Foundation

@inline(__always) func factoryBridgeTrace(_ phase: String, _ fields: [String: String] = [:]) {
    var line = "FACTORY_BRIDGE_TRACE phase=\(phase)"
    for key in fields.keys.sorted() { line += " \(key)=\(fields[key]!)" }
    line += "\r\n"
    // stderr avoids stdout buffering ambiguity seen in failed Count1r2 receipt.
    FileHandle.standardError.write(Data(line.utf8))
}

// Exact main.swift replacement markers:
//
// factoryBridgeTrace("before-bridge-load", ["path": rendererPath])
// let bridge = try Bridge.load(path: rendererPath)
// factoryBridgeTrace("after-bridge-load", [
//   "abiMajor": String(bridge.info.abi_major),
//   "abiMinor": String(bridge.info.abi_minor),
//   "pointerWidth": String(bridge.info.pointer_width),
//   "fnCount": String(bridge.info.fn_count)
// ])
// bridge.onReady = { window in
//   factoryBridgeTrace("loop-ready", ["window": String(window.handle)])
//   factoryBridgeTrace("on-ready")
//   // Emit first-window-metrics from the first actual metrics callback, not from a guessed HWND.
// }
// bridge.onEvent = { event in
//   // Keep existing event handling; emit only bounded scalar phase markers.
// }
// bridge.onWindowClosed = { factoryBridgeTrace("window-closed") }
// ... install activation hook ...
// factoryBridgeTrace("hook-install-result", ["installed": "true"])
// factoryBridgeTrace("before-bridge-run", ["hook": "installed"])
// try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)
// factoryBridgeTrace("after-bridge-run")

// Optional loader-phase probe, used only in fresh diagnostic host. It verifies
// LoadLibrary/GetProcAddress/bootstrap/get-api without changing protected Bridge.load.
#if os(Windows)
import CSwiftRight
import SwiftRightBridge
import WinSDK

enum FactoryBridgeLoaderProbeV1 {
    private typealias BootstrapFn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info>?, UInt32) -> Int32
    private typealias GetAPIFn = @convention(c) (UnsafeMutablePointer<swr_api>?, UInt32) -> Int32

    static func run(path: String) throws {
        factoryBridgeTrace("before-load-library", ["path": path])
        let module: HMODULE? = path.withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        guard let module else { throw NSError(domain: "FactoryTraceLoadLibrary", code: Int(GetLastError())) }
        defer { _ = FreeLibrary(module) }
        factoryBridgeTrace("after-load-library")

        guard let bootRaw = GetProcAddress(module, "swr_bootstrap_query") else {
            throw NSError(domain: "FactoryTraceBootstrapSymbol", code: Int(GetLastError()))
        }
        factoryBridgeTrace("before-bootstrap-query")
        let boot = unsafeBitCast(bootRaw, to: BootstrapFn.self)
        var info = swr_bootstrap_info()
        let bootRC = withUnsafeMutablePointer(to: &info) { boot($0, UInt32(MemoryLayout<swr_bootstrap_info>.size)) }
        factoryBridgeTrace("after-bootstrap-query", ["rc": String(bootRC), "abiMajor": String(info.abi_major), "abiMinor": String(info.abi_minor), "pointerWidth": String(info.pointer_width), "fnCount": String(info.fn_count)])
        guard bootRC == 0 else { throw NSError(domain: "FactoryTraceBootstrapRC", code: Int(bootRC)) }

        guard let apiRaw = GetProcAddress(module, "swr_get_api") else {
            throw NSError(domain: "FactoryTraceAPISymbol", code: Int(GetLastError()))
        }
        factoryBridgeTrace("before-get-api")
        let getAPI = unsafeBitCast(apiRaw, to: GetAPIFn.self)
        var api = swr_api()
        let apiRC = withUnsafeMutablePointer(to: &api) { getAPI($0, UInt32(MemoryLayout<swr_api>.size)) }
        factoryBridgeTrace("after-get-api", ["rc": String(apiRC), "structSize": String(api.struct_size), "fnCount": String(info.fn_count)])
        guard apiRC == 0 else { throw NSError(domain: "FactoryTraceAPIRC", code: Int(apiRC)) }
        factoryBridgeTrace("after-loader-probe")
    }
}
#endif
