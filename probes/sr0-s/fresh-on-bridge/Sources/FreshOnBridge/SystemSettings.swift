import Foundation
#if os(Windows)
import WinSDK
#endif

// Windows "Show animations in Windows" (SPI_GETCLIENTAREAANIMATION, 0x1042). The OS reports TRUE when client-area
// animations are enabled, so reduce motion is the negation. Returns nil when the platform is not Windows or the call fails.
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
