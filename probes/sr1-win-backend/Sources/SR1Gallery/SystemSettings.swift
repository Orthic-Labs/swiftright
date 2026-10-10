import Foundation
#if os(Windows)
import WinSDK
#endif

// Windows "Animation effects" / "Show animations in Windows" (SPI_GETCLIENTAREAANIMATION, 0x1042). The OS reports TRUE when
// client-area animations are enabled. Returns nil when the platform is not Windows or the call fails.
// DECISION 2026-10-10 (Adrian): app animations must work on a system that has animation effects turned off. Hosts READ and LOG
// this value (`system_reduce`) but must not map it to `accessibilityReduceMotion`; reduced motion is an explicit app or test
// override only (see probes/sr0-s/fresh-on-bridge/RESULT.md, "2026-10-10 parity pass").
func systemAnimationsEnabled() -> Bool? {
    #if os(Windows)
    var enabled: Int32 = 0
    let ok = withUnsafeMutablePointer(to: &enabled) { pointer -> Bool in
        SystemParametersInfoW(UINT(0x1042), 0, UnsafeMutableRawPointer(pointer), 0)
    }
    guard ok else { return nil }
    return enabled != 0
    #else
    return nil
    #endif
}
