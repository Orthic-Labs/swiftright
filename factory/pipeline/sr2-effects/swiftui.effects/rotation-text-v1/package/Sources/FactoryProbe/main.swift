import Foundation
import SwiftRightHost
import WinSDK

// Capture host: an owned renderer window of a fixed client size, the witness as a plain SwiftUI-source view, and the PRODUCT paint
// path (SwiftRightHost: shapes incl. continuous, Image(systemName:), body/custom fonts, line limit). Nothing here paints:
// the host only places the resolved tree (optionally centred in the viewport), draws the white/dark background, commits it
// and owns the capture lifecycle (activation veto, owned-window metrics, 10 s lease).
// Stamped per case by blocks-11-16/new-case.py (lane A: Button and List). Input is routed to the runtime as a user's would be: a pointer press/release on a hit-target
// node taps its Button or selects its List row, keys run the default-action shortcut, move focus (Tab) and move a List selection (Up/Down) or delete (Delete),
// accessibility invoke runs a Button. Every bridge event is logged as HOST_EVENT (diagnostics). --factory-capture-lease-seconds=N sets the capture lease (default 10).
// The witness file is the case's own and is never touched.

// Thread-local hook vetoes activation before the renderer creates its window (nothing ever takes the foreground).
let hostActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) { return 1 }
    return CallNextHookEx(nil, code, wParam, lParam)
}

/// Where the renderer DLL is: SWIFTRIGHT_RENDER_DLL (set per run by the capture job), else the pinned default.
func hostRendererPath() -> String {
    ProcessInfo.processInfo.environment["SWIFTRIGHT_RENDER_DLL"] ?? "D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll"
}

/// The directory holding bundled fonts: beside the exe, in a `Resources` folder there, or the same one above a SwiftPM scratch layout.
func hostBundledFontDirectory() -> URL? {
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for _ in 0..<8 {
        for candidate in [dir, dir.appendingPathComponent("Resources", isDirectory: true)] where !BundledFontLibrary.fontFiles(in: candidate).isEmpty {
            return candidate
        }
        dir.deleteLastPathComponent()
    }
    return nil
}

/// Manual-clock mode (F1, animation cases). SWIFTRIGHT_CLOCK = comma-separated seconds, SWIFTRIGHT_FRAME = index k. The host ignores display-tick times: on its first
/// display tick it calls Graph.tick(now:) at clock[0] ... clock[k] in order (flushing after each step), then holds the state of step k for the capture and prints
/// HOST_CLOCK_FRAME and HOST_GEOMETRY (the resolved frames and opacities). Without the variables nothing changes.
struct HostClock {
    let times: [Double]
    let frame: Int
    static let current: HostClock? = {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["SWIFTRIGHT_CLOCK"], !raw.isEmpty else { return nil }
        let times = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !times.isEmpty, let k = env["SWIFTRIGHT_FRAME"].flatMap({ Int($0) }), k >= 0, k < times.count else { return nil }
        return HostClock(times: times, frame: k)
    }()
}

/// Case hook (the witness is byte-identical on both platforms): Windows runs the animation as authored; the Mac clock host wraps it so SwiftUI evaluates it at the manual clock.
enum FactoryAnim {
    static func wrap(_ animation: Animation) -> Animation { animation }
}

/// Case hook for events at a manual-clock time (the same call on the Mac clock host): `FactoryClock.at(0.4) { withAnimation(...) { ... } }`. The replay runs the action at the first
/// step with time >= t, flushes, and ticks again at that time so a motion it starts begins there (a real display tick would anchor it at the next one).
@MainActor enum FactoryClock {
    private static var pending: [(Double, @MainActor () -> Void)] = []
    static func at(_ t: Double, _ action: @escaping @MainActor () -> Void) { pending.append((t, action)) }
    static func runDue(_ now: Double) -> Bool {
        let due = pending.filter { $0.0 <= now + 1e-9 }
        pending.removeAll { $0.0 <= now + 1e-9 }
        for (_, action) in due { action() }
        return !due.isEmpty
    }
}

struct HostPlacement {
    let dx: Float, dy: Float
    func applying(to b: Rect) -> Rect { Rect(x: b.x + dx, y: b.y + dy, w: b.w, h: b.h) }
    /// Centres the intrinsic root of the tree in the viewport (translation of the whole subtree; the background stays fixed).
    static func centered(_ root: Rect, in viewport: Rect) -> HostPlacement? {
        let all = [root.x, root.y, root.w, root.h, viewport.x, viewport.y, viewport.w, viewport.h]
        guard all.allSatisfy({ $0.isFinite }), root.w >= 0, root.h >= 0, root.w <= viewport.w, root.h <= viewport.h else { return nil }
        return HostPlacement(dx: viewport.x + (viewport.w - root.w) / 2 - root.x, dy: viewport.y + (viewport.h - root.h) / 2 - root.y)
    }
}

@MainActor final class CaptureHost {
    static let centered = false
    static let dark = false

    let bridge: Bridge
    var graph: Graph?
    var window: BridgeWindow?
    var measurer: BridgeTextMeasurer?
    var systemImages: SystemImageRegistry?
    var painter: ResolvedNodePainter?
    var ownedHWND: HWND?
    var initialDPI: UInt32?
    var viewport = Rect(x: 0, y: 0, w: 320, h: 240)
    var scale: Float = 1
    var version: UInt64 = 0
    var started: UInt64?
    var live: Set<UInt64> = []
    var runtimeIDs: [UInt64: String] = [:]
    var errors: [String] = []
    // The bridge drains late main-queue work after onWindowClosed; no window ownership lookup is valid then.
    var windowClosed = false
    var lastRecord: CommitRecord?
    var clockDone = false
    static let leaseNS: UInt64 = {
        for a in CommandLine.arguments where a.hasPrefix("--factory-capture-lease-seconds=") { if let n = UInt64(a.dropFirst("--factory-capture-lease-seconds=".count)), n > 0 { return n * 1_000_000_000 } }
        return 10_000_000_000
    }()
    var pressedNode: UInt64 = 0
    init(_ bridge: Bridge) { self.bridge = bridge }

    func ready(_ window: BridgeWindow) {
        self.window = window
        do {
            let abi = try window.metrics()
            let owned = try factoryOwnedClient()
            let metrics = owned.size
            ownedHWND = owned.hwnd; initialDPI = metrics.dpi
            print("HOST_ABI_INITIAL_METRICS width=\(abi.width) height=\(abi.height) scale=\(abi.scale)")
            // H17: the scale is the renderer's own report (the explicit render scale passed to run below), never GetDpiForWindow.
            scale = abi.scale
            let scaleOK = abs(abi.scale - factoryRenderScale) < 1e-4
            print("HOST_SCALE_GUARD requested=\(factoryRenderScale) renderer=\(abi.scale) clientDPI=\(metrics.dpi) status=\(scaleOK ? "PASS" : "MISMATCH")")
            guard scaleOK else { throw NSError(domain: "HostRenderScaleMismatch", code: 1) }
            viewport = Rect(x: 0, y: 0, w: Float(metrics.width), h: Float(metrics.height))
            // Bundled fonts register before the first measurement and are verified to resolve to the registered bytes.
            let fonts = BundledFontLibrary(bridge: bridge)
            if let dir = hostBundledFontDirectory() {
                for registration in try fonts.registerAll(in: dir) {
                    let resolved = try bridge.resolveFont(family: registration.family)
                    guard resolved.source == .bundled, resolved.handle == registration.handle else {
                        throw NSError(domain: "HostBundledFontNotResolved", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(registration.family): \(resolved.source)"])
                    }
                    print("HOST_BUNDLED_FONT family=\(registration.family) weight=\(registration.weight) faces=\(registration.faceCount) sha256=sha256:\(registration.sha256Hex) abi=\(bridge.revision) resolve=\(resolved.source)")
                }
            }
            let body = BodyFontProfile(try NativeWindowsBodyFontResolver.resolve(dpi: UInt32((scale * 96).rounded())))
            let measurer = BridgeTextMeasurer(bridge: bridge, scale: scale, body: body, fonts: fonts)
            self.measurer = measurer
            let images = try SystemImageRegistry(images: bridge, rasterizer: WindowsGlyphRasterizer())
            images.scale = Double(scale)
            systemImages = images
            painter = ResolvedNodePainter(images: bridge, scale: scale, text: measurer, systemImages: images)
            let graph = Graph(ZStack(alignment: .center) { Witness_e69_rotation_text() }.frame(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center), measurer: measurer, scale: CGFloat(scale))
            images.install(on: graph)
            graph.rootProposal = ProposedViewSize(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale))
            graph.commitSink = { [weak self] record in self?.commit(record) }
            self.graph = graph
            try window.requestTicks(true)
            graph.flush()
            print("HOST_RENDERER_READY scale=\(scale) width=\(metrics.width) height=\(metrics.height) hwnd=\(UInt(bitPattern: owned.hwnd)) pid=\(owned.pid) thread=\(owned.thread) dpi=\(metrics.dpi) metricsSource=owned-client-rect")
            fflush(stdout)
        } catch { fail(error) }
    }

    func fail(_ error: Error) { errors.append(String(describing: error)); bridge.requestQuit() }

    func commit(_ record: CommitRecord) {
        guard !windowClosed, let root = record.root, let window, let painter else { return }
        lastRecord = record
        if let failure = measurer?.failures.first { fail(NSError(domain: "HostTextMeasurement", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])); return }
        let rootPixel = root.pixelFrame
        let rootBounds = Rect(x: Float(rootPixel.x), y: Float(rootPixel.y), w: Float(rootPixel.width), h: Float(rootPixel.height))
        var placement = HostPlacement(dx: 0, dy: 0)
        if Self.centered {
            guard let centering = HostPlacement.centered(rootBounds, in: viewport) else { fail(NSError(domain: "HostRootCenteringMismatch", code: 1)); return }
            placement = centering
            print("HOST_ROOT_CENTERING rootX=\(rootBounds.x) rootY=\(rootBounds.y) rootW=\(rootBounds.w) rootH=\(rootBounds.h) dx=\(placement.dx) dy=\(placement.dy) viewportW=\(viewport.w) viewportH=\(viewport.h)")
        }
        do {
            let committed = try painter.commit(root: root, version: version + 1, previousLive: live,
                                               background: ResolvedNodePainter.Background(bounds: viewport, color: Self.dark ? 0x1e1e1eff : 0xffffffff),
                                               place: { placement.applying(to: $0) }) { try window.commit($0) }
            version += 1
            live = committed.live
            runtimeIDs.merge(committed.runtimeIDs) { _, new in new }
            print("HOST_COMMIT version=\(version) nodes=\(committed.nodeCount)")
            fflush(stdout)
        } catch { fail(error) }
    }

    func event(_ event: BridgeEvent) {
        guard !windowClosed else { return }
        print("HOST_EVENT kind=\(event.kindRaw) action=\(event.action) node=\(event.node) x=\(event.x) y=\(event.y) mods=\(event.modifiers) text=\(event.text) typed=\(event.typed)")
        fflush(stdout)
        guard let graph else { return }
        switch event.kind {
        case .axAction where event.action == 1:
            // the default (invoke) action of a Button runs it, of a Toggle flips it
            if let id = runtimeIDs[event.node], !graph.tapButton(id) { _ = graph.activateToggle(id) }
            graph.flush()
        case .pointer:
            // A press arms the node under the pointer; the release on the same node is the click (as AppKit and UIA buttons do).
            if event.action == 1 { pressedNode = event.node; return }
            guard event.action == 2, event.node != 0, pressedNode == event.node, let id = runtimeIDs[event.node] else { pressedNode = 0; return }
            pressedNode = 0
            var mods: EventModifiers = []
            if event.modifiers & 0x4 != 0 { mods.insert(.shift) }; if event.modifiers & 0x1 != 0 { mods.insert(.command) }
            if !graph.tapButton(id) { if graph.selectRow(id, modifiers: mods) { setListActive() } }
            graph.flush()
        case .key where event.action == 1:
            handleKey(event)
        default: break
        }
    }

    /// The selection of a List paints in the accent colour once the keyboard is in the list (a click on a row, an arrow key), grey before.
    func setListActive() {
        guard let painter, !painter.listIsActive else { return }
        painter.listIsActive = true
        if let record = lastRecord { commit(record) }
    }

    /// The List that holds the keyboard: the first one in tree order (cases have one).
    func firstListID() -> String? {
        func find(_ n: ResolvedNode) -> String? { if n.kind == "List" { return n.id }; for c in n.children { if let f = find(c) { return f } }; return nil }
        return lastRecord?.root.flatMap(find)
    }

    func handleKey(_ event: BridgeEvent) {
        guard let graph else { return }
        let name = event.text.lowercased(), shift = event.modifiers & 0x4 != 0, ctrl = event.modifiers & 0x1 != 0
        var mods: EventModifiers = []
        if ctrl { mods.insert(.command) }; if shift { mods.insert(.shift) }
        switch name {
        case "tab": _ = graph.moveFocus(forward: !shift)
        case "pageup", "pagedown":
            // PageUp/PageDown: the model route to onMove (a drag is not driven): move the selected row one place up/down
            if let list = firstListID() { _ = graph.moveSelection(in: list, by: name == "pageup" ? -1 : 1) }
        case "up", "arrowup", "down", "arrowdown":
            if let list = firstListID() {
                if graph.navigateList(list, name.hasSuffix("up") ? .up : .down, extending: shift) { setListActive() }
            }
        case "delete", "backspace":
            if let list = firstListID() { setListActive(); _ = graph.deleteSelection(in: list) }
        case "enter", "return": _ = graph.performKeyboardShortcut(.return, modifiers: mods)
        case "escape": _ = graph.performKeyboardShortcut(.escape, modifiers: mods)
        default:
            if event.typed.count == 1, let c = event.typed.lowercased().first { _ = graph.performKeyboardShortcut(KeyEquivalent(c), modifiers: mods) }
        }
        graph.flush()
    }

    func tick(_ time: UInt64) {
        guard !windowClosed else { return }
        do {
            let owned = try factoryOwnedClient(expected: ownedHWND)
            guard owned.size.dpi == initialDPI else { throw NSError(domain: "HostDPIDriftUnsupported", code: 1) }
            let width = Float(owned.size.width), height = Float(owned.size.height)
            if viewport.w != width || viewport.h != height {
                viewport = Rect(x: 0, y: 0, w: width, h: height)
                graph?.rootProposal = ProposedViewSize(width: (CGFloat(width) / CGFloat(scale)), height: (CGFloat(height) / CGFloat(scale)))
                print("HOST_VIEWPORT_UPDATE width=\(owned.size.width) height=\(owned.size.height) dpi=\(owned.size.dpi) logicalWidth=\((CGFloat(width) / CGFloat(scale))) logicalHeight=\((CGFloat(height) / CGFloat(scale)))")
                fflush(stdout)
            }
        } catch { fail(error); return }
        if started == nil { started = time }
        if let clock = HostClock.current {
            if !clockDone {
                clockDone = true
                for j in 0...clock.frame {
                    graph?.tick(now: clock.times[j])
                    graph?.flush()
                    if FactoryClock.runDue(clock.times[j]) {
                        graph?.flush()
                        graph?.tick(now: clock.times[j])
                        graph?.flush()
                    }
                }
                print("HOST_CLOCK_FRAME index=\(clock.frame) t=\(clock.times[clock.frame]) times=\(clock.times)")
                if let root = lastRecord?.root { print("HOST_GEOMETRY " + Self.geometryJSON(root, version: version)) }
                fflush(stdout)
            }
        } else {
            graph?.tick(now: Double(time) / 1_000_000_000)
            graph?.flush()
        }
        if time - (started ?? time) > Self.leaseNS { bridge.requestQuit() }
    }

    /// Resolved tree as JSON: one row per node (pre-order) with its path id, kind, presented frame in points and opacity.
    static func geometryJSON(_ root: ResolvedNode, version: UInt64) -> String {
        var rows: [String] = []
        func visit(_ n: ResolvedNode) {
            let f = n.frame
            rows.append("{\"id\":\"\(n.id)\",\"kind\":\"\(n.kind)\",\"x\":\(f.minX),\"y\":\(f.minY),\"w\":\(f.width),\"h\":\(f.height),\"opacity\":\(n.opacity)}")
            n.children.forEach(visit)
        }
        visit(root)
        return "{\"commit\":\(version),\"nodes\":[" + rows.joined(separator: ",") + "]}"
    }

    func closed() {
        guard !windowClosed else { return }
        windowClosed = true
        graph?.tearDown()
        measurer?.releaseAll()
        painter?.releaseAll()
        systemImages?.releaseAll()
        do { try bridge.shutdownComplete() } catch { errors.append(String(describing: error)) }
    }
}

/// The density every gate was fitted at (decision C12 on the Mac). Passed to the renderer as an explicit render scale (decision H17).
let factoryRenderScale: Float = 2.5

let result: Int32 = MainActor.assumeIsolated {
    do {
        let dll = hostRendererPath()
        let bridge = try Bridge.load(path: dll)
        print("HOST_RENDERER dll=\(dll) abi=\(bridge.revision) fonts=\(bridge.supportsFontRegistration)")
        let host = CaptureHost(bridge)
        bridge.onReady = { window in MainActor.assumeIsolated { host.ready(window) } }
        bridge.onEvent = { event in MainActor.assumeIsolated { host.event(event) } }
        bridge.onTick = { _, time in MainActor.assumeIsolated { host.tick(time) } }
        bridge.onWindowClosed = { MainActor.assumeIsolated { host.closed() } }
        guard let activationHook = SetWindowsHookExW(Int32(WH_CBT), hostActivationVeto, nil, GetCurrentThreadId()) else {
            print("HOST_STARTUP_ERROR activation veto hook failed"); return 78
        }
        defer { UnhookWindowsHookEx(activationHook) }
        print("HOST_BACKGROUND_GUARD thread-cbt-activation-veto")
        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240, renderScale: factoryRenderScale)
        host.errors.forEach { print("HOST_RENDER_ERROR \($0)") }
        return host.errors.isEmpty ? 0 : 1
    } catch { print("HOST_STARTUP_ERROR \(error)"); return 78 }
}
fflush(stdout)
exit(result)
