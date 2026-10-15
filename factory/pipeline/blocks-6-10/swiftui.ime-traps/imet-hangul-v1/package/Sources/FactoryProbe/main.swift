import Foundation
import SwiftRightHost
import WinSDK

// Capture host: an owned renderer window of a fixed client size, the witness as a plain SwiftUI-source view, and the PRODUCT paint
// path (SwiftRightHost: shapes incl. continuous, Image(systemName:), body/custom fonts, line limit). Nothing here paints:
// the host only places the resolved tree (optionally centred in the viewport), draws the white/dark background, commits it
// and owns the capture lifecycle (activation veto, owned-window metrics, 10 s lease).
// Stamped per case by blocks-6-10/make-text-cases.py (text-hosts/windows); the witness file is the case's own and is never touched.
// Lane B (text input, blocks 13-15): HostTextInput (product code) is the bridge's TextStore and routes pointer, key and accessibility events to
// the focused TextField; the commit passes the focused field to the renderer. `SCRIPT` below is an in-process input script run on display ticks: it
// drives the same TextStore calls the renderer makes from WM_IME_COMPOSITION / WM_CHAR (compose = ime_replace_and_mark, commit = ime_replace,
// cancel = ime_replace_and_mark with empty text), for the cases whose Windows Sandbox has no IME to compose with (the F2 `ime` step is refused by
// ImmGetContext across processes). HOST_FIELD / HOST_SCRIPT lines record the text model after each commit and script step: measurements, not gates.

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
    var input: HostTextInput?
    var scriptIndex = 0
    var lastScriptTick: UInt64 = 0
    var clockDone = false
    init(_ bridge: Bridge) { self.bridge = bridge }

    func ready(_ window: BridgeWindow) {
        self.window = window
        do {
            let abi = try window.metrics()
            let owned = try factoryOwnedClient()
            let metrics = owned.size
            ownedHWND = owned.hwnd; initialDPI = metrics.dpi
            print("HOST_ABI_INITIAL_METRICS width=\(abi.width) height=\(abi.height) scale=\(abi.scale)")
            scale = metrics.scale
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
            let body = BodyFontProfile(try NativeWindowsBodyFontResolver.resolve(dpi: metrics.dpi))
            let measurer = BridgeTextMeasurer(bridge: bridge, scale: scale, body: body, fonts: fonts)
            self.measurer = measurer
            let images = try SystemImageRegistry(images: bridge, rasterizer: WindowsGlyphRasterizer())
            images.scale = Double(scale)
            systemImages = images
            painter = ResolvedNodePainter(images: bridge, scale: scale, text: measurer, systemImages: images)
            let graph = Graph(Witness_imet_imethangulv1(), measurer: measurer, scale: CGFloat(scale))
            images.install(on: graph)
            graph.rootProposal = ProposedViewSize(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale))
            graph.commitSink = { [weak self] record in self?.commit(record) }
            self.graph = graph
            let input = HostTextInput(graph: graph, runtimeID: { [weak self] in self?.runtimeIDs[$0] }, layout: { [weak self] in self?.painter?.fieldLayouts[$0] })
            self.input = input
            bridge.textStore = input
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
                                               place: { placement.applying(to: $0) }, focused: record.focused) { try window.commit($0) }
            version += 1
            live = committed.live
            runtimeIDs.merge(committed.runtimeIDs) { _, new in new }
            print("HOST_COMMIT version=\(version) nodes=\(committed.nodeCount) focused=\(record.focused ?? "none")")
            logFields(root, tag: "commit")
            fflush(stdout)
        } catch { fail(error) }
    }

    /// The text model of every TextField after a commit or a script step.
    func logFields(_ root: ResolvedNode, tag: String) {
        func visit(_ n: ResolvedNode) {
            if n.kind == "TextField", let s = graph?.textInput(n.id) {
                let m = s.markedRange.map { "\($0.location)+\($0.length)" } ?? "none"
                print("HOST_FIELD tag=\(tag) id=\(n.id) committed=\(s.committed.debugDescription) display=\(s.display.debugDescription) selection=\(s.selection.location)+\(s.selection.length) marked=\(m) focused=\(graph?.focusedTextFieldID == n.id)")
            }
            n.children.forEach(visit)
        }
        visit(root)
    }

    func event(_ event: BridgeEvent) {
        guard !windowClosed else { return }
        if event.kind == .key || event.kind == .pointer || event.kind == .ime || (event.kind == .axAction && event.action != 1) {
            print("HOST_EVENT kind=\(event.kind.map { "\($0)" } ?? "?") action=\(event.action) node=\(event.node) text=\(event.text.debugDescription) typed=\(event.typed.debugDescription) mods=\(event.modifiers)")
        }
        if input?.handle(event) == true {
            if let root = lastRecord?.root { logFields(root, tag: "event") }
            fflush(stdout)
            return
        }
        // a pointer release over a Button runs it, over a Toggle flips it (the renderer reports the hit node; presses are left to text input)
        if event.kind == .pointer, event.action == 2, let id = runtimeIDs[event.node] {
            if !(graph?.tapButton(id) ?? false) { _ = graph?.activateToggle(id) }
            graph?.flush()
            return
        }
        if event.kind == .axAction, event.action == 1, let id = runtimeIDs[event.node] {
            // the default (invoke) action of a Button runs it, of a Toggle flips it
            if !(graph?.tapButton(id) ?? false) { _ = graph?.activateToggle(id) }
            graph?.flush()
        }
    }

    func tick(_ time: UInt64) {
        guard !windowClosed else { return }
        do {
            let owned = try factoryOwnedClient(expected: ownedHWND)
            guard owned.size.dpi == initialDPI else { throw NSError(domain: "HostDPIDriftUnsupported", code: 1) }
            let width = Float(owned.size.width), height = Float(owned.size.height)
            if viewport.w != width || viewport.h != height {
                viewport = Rect(x: 0, y: 0, w: width, h: height)
                graph?.rootProposal = ProposedViewSize(width: owned.size.logicalWidth, height: owned.size.logicalHeight)
                print("HOST_VIEWPORT_UPDATE width=\(owned.size.width) height=\(owned.size.height) dpi=\(owned.size.dpi) logicalWidth=\(owned.size.logicalWidth) logicalHeight=\(owned.size.logicalHeight)")
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
        runScript(time)
        if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }
    }

    /// In-process input script (stamped): one step per 150 ms of display time, starting 300 ms after the first tick.
    static let script: [[String: Any]] = {
        guard let data = "[{\"op\":\"click\",\"field\":0,\"x\":150},{\"op\":\"compose\",\"text\":\"\\u314e\"},{\"op\":\"compose\",\"text\":\"\\ud558\"},{\"op\":\"compose\",\"text\":\"\\ud55c\"},{\"op\":\"commit\",\"text\":\"\\ud55c\"},{\"op\":\"compose\",\"text\":\"\\u3131\"},{\"op\":\"compose\",\"text\":\"\\uadf8\"},{\"op\":\"compose\",\"text\":\"\\uae00\"},{\"op\":\"commit\",\"text\":\"\\uae00\"}]".data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return any
    }()

    func runScript(_ time: UInt64) {
        guard scriptIndex < Self.script.count, let started, let input, let graph, version > 0 else { return }
        guard time - started >= 300_000_000, time - lastScriptTick >= 150_000_000 else { return }
        lastScriptTick = time
        let step = Self.script[scriptIndex]
        scriptIndex += 1
        let op = step["op"] as? String ?? ""
        let text = step["text"] as? String ?? ""
        let fieldIndex = (step["field"] as? Int) ?? 0
        func bridgeNode(_ id: String?) -> UInt64? { id.flatMap { graph.nodeInstance($0) }.map { UInt64($0 + 1) } }
        let focusedNode = bridgeNode(graph.focusedTextFieldID)
        var ok = true
        switch op {
        case "focus":
            let ids = graph.ids(ofKind: "TextField")
            if fieldIndex < ids.count, let node = bridgeNode(ids[fieldIndex]) { ok = input.accessibility(.focus, node: node, i0: 0, i1: 0, text: "") } else { ok = false }
        case "caret":
            if let id = graph.focusedTextFieldID, let s = graph.textInput(id) { ok = s.setSelection(UTF16Range(location: (step["offset"] as? Int) ?? 0, length: (step["length"] as? Int) ?? 0)); graph.flush() } else { ok = false }
        case "click":
            // a pointer press on field fieldIndex at x (points, as the Mac step): focus and caret, through the product pointer path (a focus change ends the other field's composition)
            if fieldIndex < graph.ids(ofKind: "TextField").count, let node = bridgeNode(graph.ids(ofKind: "TextField")[fieldIndex]) {
                ok = input.pointerDown(node: node, x: Float((step["x"] as? NSNumber)?.doubleValue ?? 0) * scale)
            } else { ok = false }
        case "compose":
            ok = focusedNode.map { input.replaceAndMark(node: $0, range: nil, text: Array(text.utf16), newSelection: nil) } ?? false
        case "composeAt":
            // compose over an explicit UTF-16 range [start, end) (block 15 traps: an invalid or inverted region must be refused, never crash)
            let span = UTF16Span(start: UInt32(truncatingIfNeeded: (step["start"] as? Int) ?? 0), end: UInt32(truncatingIfNeeded: (step["end"] as? Int) ?? 0))
            ok = focusedNode.map { input.replaceAndMark(node: $0, range: span, text: Array(text.utf16), newSelection: nil) } ?? false
        case "commit":
            ok = focusedNode.map { input.replace(node: $0, range: nil, text: Array(text.utf16)) } ?? false
        case "cancel":
            ok = focusedNode.map { input.replaceAndMark(node: $0, range: nil, text: [], newSelection: nil) } ?? false
        case "key":
            var mods: UInt32 = 0
            for m in (step["mods"] as? [String] ?? []) { if m == "shift" { mods |= 4 } else if m == "ctrl" { mods |= 1 } else if m == "alt" { mods |= 2 } }
            ok = input.handleKey(name: step["name"] as? String ?? "", modifiers: mods)
        default: ok = false
        }
        print("HOST_SCRIPT i=\(scriptIndex - 1) op=\(op) text=\(text.debugDescription) ok=\(ok)")
        if let root = lastRecord?.root { logFields(root, tag: "script") }
        fflush(stdout)
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
        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)
        host.errors.forEach { print("HOST_RENDER_ERROR \($0)") }
        return host.errors.isEmpty ? 0 : 1
    } catch { print("HOST_STARTUP_ERROR \(error)"); return 78 }
}
fflush(stdout)
exit(result)
