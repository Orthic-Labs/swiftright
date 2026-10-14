import AppKit
import SwiftUI

// Mac capture host for animation cases (F1, manual clock). An NSHostingView in a never-shown borderless window, drawn with cacheDisplay into a bitmap of
// 320x240 pt * scale, once per clock step. usage: host --scale 2.5 --clock 0,0.1,0.2 --out DIR --prefix run-01   (writes DIR/<prefix>-f00.png ...)
//
// The case's Witness.swift is byte-identical to the Windows package's and builds its animations through `FactoryAnim.wrap(_:)`. Here that wraps the SwiftUI
// Animation in a CustomAnimation that forwards to the ORIGINAL animation (`Animation.animate(value:time:context:)`, public since macOS 15) but with `time` taken
// from ManualClock.now - (the clock value when the animation first ran) instead of the wall clock. SwiftUI's own render loop still drives the view; the host moves the
// clock, waits until SwiftUI has evaluated the animation at the new time, and captures. The curve, merging and completion are SwiftUI's own; only time is ours.

@MainActor
enum ManualClock {
    nonisolated(unsafe) static var now = 0.0
    nonisolated(unsafe) static var observedNow = -1.0
    nonisolated(unsafe) static var lastLog = ""
    nonisolated(unsafe) static var nextID = 0
}

func clockLeaves(_ x: Any, _ out: inout [Double]) {
    if let d = x as? Double { out.append(d); return }
    if let d = x as? CGFloat { out.append(Double(d)); return }
    for c in Mirror(reflecting: x).children { clockLeaves(c.value, &out) }
}

final class ClockStart: @unchecked Sendable {
    var start: Double?
    let id: Int
    init(id: Int) { self.id = id }
}

struct ManualAnimation: CustomAnimation {
    let base: Animation
    let box: ClockStart

    static func == (a: ManualAnimation, b: ManualAnimation) -> Bool { a.base == b.base }
    func hash(into hasher: inout Hasher) { hasher.combine(base) }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let now = ManualClock.now
        if box.start == nil { box.start = now }
        let local = now - (box.start ?? now)
        let result = base.animate(value: value, time: local, context: &context)
        var v: [Double] = [], r: [Double] = []
        clockLeaves(value, &v)
        if let result { clockLeaves(result, &r) }
        ManualClock.lastLog = "anim=\(box.id) time=\(local) value=\(v) result=\(r) ended=\(result == nil)"
        ManualClock.observedNow = now
        return result
    }

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool {
        base.shouldMerge(previous: previous, value: value, time: ManualClock.now - (box.start ?? ManualClock.now), context: &context)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        base.velocity(value: value, time: ManualClock.now - (box.start ?? ManualClock.now), context: context)
    }
}

enum FactoryAnim {
    @MainActor static func wrap(_ animation: Animation) -> Animation {
        ManualClock.nextID += 1
        return Animation(ManualAnimation(base: animation, box: ClockStart(id: ManualClock.nextID)))
    }
}

/// Case hook for events at a manual-clock time (the interruption at 40 %, a state change after a transition ...): `FactoryClock.at(0.4) { withAnimation(...) { ... } }`.
/// The action runs on the main actor at the first clock step with time >= t, before the host waits for SwiftUI to evaluate that step.
@MainActor
enum FactoryClock {
    private static var pending: [(Double, @MainActor () -> Void)] = []
    static func at(_ t: Double, _ action: @escaping @MainActor () -> Void) { pending.append((t, action)) }
    static func runDue(_ now: Double) {
        let due = pending.filter { $0.0 <= now + 1e-9 }
        pending.removeAll { $0.0 <= now + 1e-9 }
        for (_, action) in due { action() }
    }
}

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@MainActor
func pump(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

@main
struct ClockCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let scale = Double(value("--scale") ?? "2.5") ?? 2.5
        guard let out = value("--out"), let times = value("--clock")?.split(separator: ",").compactMap({ Double($0) }), !times.isEmpty else {
            throw NSError(domain: "MacClockHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "--out and --clock required"])
        }
        let prefix = value("--prefix") ?? "run"
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        // The first animate call fixes the animation's start, so the clock reads times[0] from before the witness appears.
        ManualClock.now = times[0]
        // SwiftUI's built-in spring ends when the remaining displacement is under about one device pixel (1.05 / displayScale pt for a size, 0.5 / displayScale for an
        // offset; the default spring on a 150 pt width ends at 0.5875 s at scale 1, 0.65 s at 2, 0.675 s at 2.5), and the scale otherwise comes from whatever screen
        // the Mac has attached (a headless 1920x1080 at 1x, a Retina panel at 2x). The reference is pinned (decision C11) to the capture density, the scale the Windows
        // runtime's Graph runs at: `--display-scale` overrides.
        let displayScale = Double(value("--display-scale") ?? "") ?? scale
        PinnedScaleWindow.pinned = CGFloat(displayScale)
        let root = ZStack(alignment: .center) { Witness_anim_easeinout() }
            .frame(width: 320, height: 240, alignment: .center)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.displayScale, displayScale)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let window = PinnedScaleWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        ScalePin.report(window: window)
        host.layoutSubtreeIfNeeded()
        pump(0.3)
        for (k, t) in times.enumerated() {
            ManualClock.now = t
            FactoryClock.runDue(t)
            var waited = 0.0
            while ManualClock.observedNow != t && waited < 0.5 { pump(0.01); waited += 0.01 }
            pump(0.08)   // let the layer tree commit what SwiftUI just evaluated
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(320 * scale), pixelsHigh: Int(240 * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacClockHost", code: 2) }
            rep.size = NSSize(width: 320, height: 240)
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacClockHost", code: 3) }
            let name = String(format: "%@-f%02d.png", prefix, k)
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
            print("MAC_FRAME index=\(k) t=\(t) observed=\(ManualClock.observedNow == t) \(ManualClock.lastLog) png=\(name)")
        }
        print("{\"status\":\"OBSERVED\",\"mode\":\"offscreen-hosting-view-manual-clock\",\"scale\":\(scale),\"frames\":\(times.count)}")
    }
}

/// The window reports the pinned backing scale instead of the attached screen's (decision C11): SwiftUI lays text out and settles springs for the scale it sees.
final class PinnedScaleWindow: NSWindow {
    nonisolated(unsafe) static var pinned: CGFloat = 1
    override var backingScaleFactor: CGFloat { Self.pinned }
}
