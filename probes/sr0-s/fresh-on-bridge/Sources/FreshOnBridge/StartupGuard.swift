import Foundation
import SwiftRightBridge

enum SR0StartupGuardError: Error, CustomStringConvertible {
    case activationHookInstallFailed

    var description: String {
        switch self {
        case .activationHookInstallFailed: return "SetWindowsHookExW(WH_CBT) failed"
        }
    }
}

#if os(Windows)
import WinSDK

private let sr0ActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) {
        return 1
    }
    return CallNextHookEx(nil, code, wParam, lParam)
}

/// Opt-in, thread-local window guard. It remains active for the complete bridge run.
final class SR0ActivationGuard {
    private var hook: HHOOK?

    init(enabled: Bool) throws {
        guard enabled else { return }
        guard let installed = SetWindowsHookExW(Int32(WH_CBT), sr0ActivationVeto, nil, GetCurrentThreadId()) else {
            throw SR0StartupGuardError.activationHookInstallFailed
        }
        hook = installed
    }

    func stop() {
        if let hook {
            _ = UnhookWindowsHookEx(hook)
            self.hook = nil
        }
    }

    deinit { stop() }
}
#else
/// Non-Windows source keeps command-line parsing portable; guard is a no-op there.
final class SR0ActivationGuard {
    init(enabled: Bool) throws {}
    func stop() {}
}
#endif

@MainActor
func emitRendererReadyTelemetry(_ window: BridgeWindow, path: String) {
    do {
        let metrics = try window.metrics()
        let object: [String: Any] = [
            "record": "renderer-ready",
            "phase": "first-ready",
            "source": "Bridge.onReady",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bridge_window": String(window.handle),
            "width_px": Int(metrics.width),
            "height_px": Int(metrics.height),
            "scale": Double(metrics.scale),
            "active": metrics.active,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: [.withoutOverwriting])
        print("SR0_RENDERER_READY file=created path=\(path) phase=first-ready")
        fflush(stdout)
    } catch {
        print("SR0_RENDERER_READY file=FAILED path=\(path) error=\(error)")
        fflush(stdout)
    }
}
