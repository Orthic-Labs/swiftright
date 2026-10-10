import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WinSDK

// Thread-local factory hook vetoes activation before staged renderer creates its window.
let factoryActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) { return 1 }
    return CallNextHookEx(nil, code, wParam, lParam)
}

@MainActor final class NativeMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    init(_ bridge: Bridge, _ scale: Float) { self.bridge = bridge; self.scale = scale }
    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        do {
            let result = try bridge.measure(MeasureRequest(text: request.text, fontFamily: "Segoe UI",
              fontSize: 16, lineHeight: 24, scale: scale,
              maxWidth: Float(request.proposedWidth ?? 0) * scale))
            bridge.release(result.run)
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(result.width / scale),
              height: CGFloat(result.height / scale)), baseline: CGFloat(result.firstBaseline / scale), lineCount: result.lineCount)
        } catch { fatalError("Native measurement failed: \(error)") }
    }
}
@MainActor final class RendererHost {
    let bridge: Bridge
    var graph: Graph?
    var window: BridgeWindow?
    let themeDark = "light" == "dark"
    var viewport = Rect(x: 0, y: 0, w: 320, h: 240)
    var scale: Float = 1
    var version: UInt64 = 0
    var started: UInt64?
    var live: Set<UInt64> = []
    var runtimeIDs: [UInt64: String] = [:]
    var errors: [String] = []
    init(_ bridge: Bridge) { self.bridge = bridge }
    func ready(_ window: BridgeWindow) {
        self.window = window
        do {
            let metrics = try window.metrics()
            scale = metrics.scale
            viewport = Rect(x: 0, y: 0, w: Float(metrics.width), h: Float(metrics.height))
            let graph = Graph(Witness_disabled(), measurer: NativeMeasurer(bridge, scale), scale: CGFloat(scale))
            graph.rootProposal = ProposedViewSize(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale))
            graph.commitSink = { [weak self] record in self?.commit(record) }
            self.graph = graph
            try window.requestTicks(true)
            graph.flush()
            print("FACTORY_RENDERER_READY scale=\(scale) width=\(metrics.width) height=\(metrics.height)")
            fflush(stdout)
        } catch { fail(error) }
    }
    func fail(_ error: Error) { errors.append(String(describing: error)); bridge.requestQuit() }
    func commit(_ record: CommitRecord) {
        guard let root = record.root, let window else { return }
        let backgroundID = UInt64.max - 1
        var nodes: [NodeUpsert] = [NodeUpsert(id: backgroundID, bounds: viewport, primitives: [.rect(viewport, color: themeDark ? 0x1e1e1eff : 0xffffffff)])]
        var runs: [TextRunHandle] = []
        var current: Set<UInt64> = []
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32) throws {
            let id = UInt64(n.instance + 1)
            current.insert(id)
            runtimeIDs[id] = n.id
            let p = n.pixelFrame
            let bounds = Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height))
            var primitives: [Primitive] = []
            var semantic: SemanticNode?
            var flags: NodeFlags = []
            switch n.kind {
            case "Text":
                if let text = n.text, !text.isEmpty {
                    let measured = try bridge.measure(MeasureRequest(text: text, fontFamily: "Segoe UI", color: themeDark ? 0xffffffff : 0x1f1f1fff, fontSize: 16,
                      lineHeight: 24, scale: scale, maxWidth: bounds.w))
                    runs.append(measured.run)
                    primitives = [.text(measured.run, x: bounds.x, y: bounds.y)]
                    semantic = SemanticNode(role: .staticText, label: text, identifier: n.id, disabled: !n.accessibility.isEnabled)
                }
            case "Button":
                let enabled = n.accessibility.isEnabled
                primitives = [.rect(bounds, color: enabled ? 0x2563ebff : 0xaaaaaaff, radius: 6 * scale)]
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .button, label: n.accessibility.label ?? n.children.first?.text ?? "",
                  actions: enabled ? [.invoke, .focus] : [], identifier: n.id, disabled: !enabled)
            case "VStack", "HStack", "Group", "EmptyView": break
            default:
                if !n.kind.hasPrefix("modifier.") && !n.kind.hasPrefix("Witness_") && n.kind != "Root" {
                    throw NSError(domain: "FactoryRendererUnsupportedNode", code: 1, userInfo: [NSLocalizedDescriptionKey: n.kind])
                }
            }
            nodes.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds, primitives: primitives, semantic: semantic))
            for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index)) }
        }
        do {
            try walk(root, parent: backgroundID, order: 0)
            current.insert(backgroundID)
            version += 1
            try window.commit(Transaction(version: version, upserts: nodes, removes: Array(live.subtracting(current))))
            live = current
            print("FACTORY_COMMIT version=\(version) nodes=\(nodes.count)")
            fflush(stdout)
        } catch { fail(error) }
        runs.forEach { bridge.release($0) }
    }
    func event(_ event: BridgeEvent) {
        if event.kind == .axAction, event.action == 1, let id = runtimeIDs[event.node] {
            _ = graph?.tapButton(id)
            graph?.flush()
        }
    }
    func tick(_ time: UInt64) {
        if started == nil { started = time }
        graph?.tick(now: Double(time) / 1_000_000_000)
        graph?.flush()
        if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }
    }
}
let result: Int32 = MainActor.assumeIsolated {
    do {
        let bridge = try Bridge.load(path: "D:\\Claude\\sr0-r09\\renderer\\swiftright_render.dll")
        let host = RendererHost(bridge)
        bridge.onReady = { window in MainActor.assumeIsolated { host.ready(window) } }
        bridge.onEvent = { event in MainActor.assumeIsolated { host.event(event) } }
        bridge.onTick = { _, time in MainActor.assumeIsolated { host.tick(time) } }
        bridge.onWindowClosed = { MainActor.assumeIsolated {
            host.graph?.tearDown()
            do { try bridge.shutdownComplete() } catch { host.errors.append(String(describing: error)) }
        } }
        guard let activationHook = SetWindowsHookExW(Int32(WH_CBT), factoryActivationVeto, nil, GetCurrentThreadId()) else {
            print("FACTORY_STARTUP_ERROR activation veto hook failed"); return 78
        }
        defer { UnhookWindowsHookEx(activationHook) }
        print("FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto")
        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)
        host.errors.forEach { print("FACTORY_RENDER_ERROR \($0)") }
        return host.errors.isEmpty ? 0 : 1
    } catch { print("FACTORY_STARTUP_ERROR \(error)"); return 78 }
}
fflush(stdout)
exit(result)
