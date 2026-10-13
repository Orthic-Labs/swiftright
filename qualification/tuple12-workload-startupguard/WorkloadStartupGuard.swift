import Foundation
import SwiftRightBridge

enum SR0WorkloadStartupGuardError: Error, CustomStringConvertible {
    case activationHookInstallFailed

    var description: String {
        switch self {
        case .activationHookInstallFailed: return "SetWindowsHookExW(WH_CBT) failed"
        }
    }
}

#if os(Windows)
import WinSDK

private let sr0WorkloadActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) {
        return 1
    }
    return CallNextHookEx(nil, code, wParam, lParam)
}

/// Opt-in same-thread guard. Lifetime covers full `Bridge.run`, including window creation & teardown.
final class SR0WorkloadStartupGuard {
    private var hook: HHOOK?

    init(enabled: Bool) throws {
        guard enabled else { return }
        guard let installed = SetWindowsHookExW(Int32(WH_CBT), sr0WorkloadActivationVeto, nil, GetCurrentThreadId()) else {
            throw SR0WorkloadStartupGuardError.activationHookInstallFailed
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
/// Keeps source portable for macOS package parsing; Windows guard is the qualified path.
final class SR0WorkloadStartupGuard {
    init(enabled: Bool) throws {}
    func stop() {}
}
#endif
