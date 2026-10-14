import AppKit
import SwiftUI

// Decision C12 (see docs/sr1-decisions.md): a Mac reference must not depend on the screen the Mac has attached. SwiftUI reads the scale of the window it is hosted in
// (and AppKit draws text and controls for it); a window with no override reports its screen's scale, which differs between a Retina panel (2x) and a headless
// 1920x1080 (1x). Every Mac capture host therefore creates its window as a `ScalePinnedWindow` (or overrides `backingScaleFactor` with `ScalePin.scale`) and calls
// `ScalePin.report(window:)` (hosts without a window: `ScalePin.reportRenderer(scale:)`), which prints one `MAC_ENV` line that `factory/tools/pair.py` parses and
// compares with the case's capture scale: a run whose pinned display scale, window backing scale or effective SwiftUI `displayScale` differs fails.
// `pair.py` compiles this file with every Mac host that mentions `ScalePin.`; it is not copied into the cases.
// The pinned scale is `--display-scale` when given (an experiment; the guard then fails the run), else `--scale` (the capture density, the scale the Windows runtime runs at), else 2.5.

enum ScalePin {
    static func argument(_ key: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static let scale: CGFloat = CGFloat(Double(argument("--display-scale") ?? argument("--scale") ?? "") ?? 2.5)

    nonisolated(unsafe) static var seen: Double = -1

    /// Reads the `displayScale` SwiftUI hands a view; the body records it while it evaluates.
    struct Probe: View {
        @Environment(\.displayScale) private var displayScale
        var body: some View {
            ScalePin.seen = Double(displayScale)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    static func screens() -> String {
        NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\($0.backingScaleFactor)x" }.joined(separator: ",")
    }

    @MainActor
    static func emit(backing: String, effective: Double) {
        print("MAC_ENV os=\(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: " ", with: "_")) pinnedDisplayScale=\(Double(scale)) windowBackingScale=\(backing) effectiveDisplayScale=\(effective) screens=[\(screens())]")
    }

    /// For a host that draws through a window: the window's backing scale, and the `displayScale` SwiftUI gives a view hosted in a throwaway window of the same class.
    @MainActor
    static func report(window: NSWindow) {
        seen = -1
        let probe = NSHostingView(rootView: Probe())
        probe.frame = NSRect(x: 0, y: 0, width: 10, height: 10)
        let scratch = type(of: window).init(contentRect: probe.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        scratch.contentView = probe
        probe.layoutSubtreeIfNeeded()   // evaluates the probe's body now; NO run-loop turn here: a pump between the case window's contentView and its first order-front changed which field the first Tab reached (focus-state/tab-order-v1, 20/20 semantic failures)
        emit(backing: "\(Double(window.backingScaleFactor))", effective: seen)
    }

    /// For a host that draws with ImageRenderer (no window): the `displayScale` SwiftUI gives a view rendered at `scale`.
    @MainActor
    static func reportRenderer(scale renderScale: Double) {
        seen = -1
        let renderer = ImageRenderer(content: Probe())
        renderer.scale = renderScale
        _ = renderer.cgImage
        emit(backing: "none", effective: seen)
    }
}

final class ScalePinnedWindow: NSWindow {
    override var backingScaleFactor: CGFloat { ScalePin.scale }
}
