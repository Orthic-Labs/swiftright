#if os(Windows)
import SharedScreens

// Synchronous entry (not async main); constructs the shared root without rendering.
@main
struct WindowsProbeEntry {
    @MainActor
    static func main() {
        let root = makeProbeRoot()
        _ = root
    }
}
#endif
