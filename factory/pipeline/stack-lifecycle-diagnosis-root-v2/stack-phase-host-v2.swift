// Additive fresh-host proposal. Do not edit protected renderer, Bridge, runtime, or ABI.
import Foundation

#if os(Windows)
import struct WinSDK.LARGE_INTEGER
import func WinSDK.QueryPerformanceCounter
#endif

/// Writes bounded scalar lifecycle evidence. Caller supplies run identity once & keeps it fixed.
struct FactoryStackPhaseWriterV2 {
    let runId: String
    let hostPid: UInt32
    let hostStartedUtc: String
    let hostPath: String
    let sessionId: UInt32
    let sourceHash: String
    let rendererHash: String
    let bridgeHash: String
    let runtimeHash: String
    private let startedTicks: UInt64 = DispatchTime.now().uptimeNanoseconds

    func write(_ phase: String, hwnd: UInt64? = nil) {
        let monoMs = (DispatchTime.now().uptimeNanoseconds - startedTicks) / 1_000_000
        var qpc: Int64 = 0
        #if os(Windows)
        var counter = LARGE_INTEGER()
        _ = QueryPerformanceCounter(&counter)
        qpc = counter.QuadPart
        #endif
        let utc = ISO8601DateFormatter().string(from: Date())
        var line = "FACTORY_STACK_PHASE_V2 runId=\(safe(runId)) hostPid=\(hostPid) hostStartedUtc=\(safe(hostStartedUtc)) hostPath=\(safe(hostPath)) sessionId=\(sessionId) sourceHash=\(sourceHash) rendererHash=\(rendererHash) bridgeHash=\(bridgeHash) runtimeHash=\(runtimeHash) phase=\(safe(phase)) monoMs=\(monoMs) qpc=\(qpc) utc=\(safe(utc))"
        if let hwnd { line += " hwnd=\(hwnd)" }
        line += "\r\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_").replacingOccurrences(of: " ", with: "_")
    }
}

// Fresh host call order, without changing protected behavior:
// before-bridge-load -> after-bridge-load -> hook-installed -> before-bridge-run
// -> dpi-configured -> loop-ready -> on-ready -> first-window-metrics
// -> window-closed -> after-bridge-run.
// First-window-metrics must come from actual callback data. Missing phases remain missing.
