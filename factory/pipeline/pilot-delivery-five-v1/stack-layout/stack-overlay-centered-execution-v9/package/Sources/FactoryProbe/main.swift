import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WinSDK

// Thread-local factory hook vetoes activation before staged renderer creates its window.
let factoryActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) { return 1 }
    return CallNextHookEx(nil, code, wParam, lParam)
}

@MainActor final class NativeMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    let bodyFont: FactoryDefaultBodyFontPolicy
    var retained: [TextMeasureRequest: SwiftRightBridge.TextMeasurement] = [:]
    init(_ bridge: Bridge, _ scale: Float, _ bodyFont: FactoryDefaultBodyFontPolicy) {
        self.bridge = bridge; self.scale = scale; self.bodyFont = bodyFont
    }
    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        do {
            guard request.fontID == "body", request.fontMetadata == nil, request.lineLimit == nil,
                  Float(request.scale) == scale else { throw NSError(domain: "FactoryUnsupportedMeasurementStyle", code: 1) }
            let result: SwiftRightBridge.TextMeasurement
            if let cached = retained[request] { result = cached }
            else {
                guard retained.count < 128 else { throw NSError(domain: "FactoryMeasurementCacheBound", code: 1) }
                result = try bridge.measure(MeasureRequest(text: request.text, fontFamily: bodyFont.family,
                  weight: bodyFont.weight, color: 0x1f1f1fff, fontSize: bodyFont.fontSizeDIP,
                  lineHeight: bodyFont.lineHeightDIP, scale: scale,
                  maxWidth: Float(request.proposedWidth ?? 0) * scale))
                retained[request] = result
                print("FACTORY_MEASURE text=\(request.text) proposedDIP=\(request.proposedWidth.map(String.init(describing:)) ?? "nil") widthPX=\(result.width) heightPX=\(result.height) lines=\(result.lineCount) scale=\(scale)")
            }
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(result.width / scale),
              height: CGFloat(result.height / scale)), baseline: CGFloat(result.firstBaseline / scale), lineCount: result.lineCount)
        } catch { fatalError("Native measurement failed: \(error)") }
    }
    func renderRun(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle {
        // Match full supported semantic style &possible edge-snapped extents.
        // Proposed widths remain in retained keys; ambiguous unequal shaping is refused.
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        let candidates = retained.filter { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale && $0.key.lineLimit == nil && factorySnappedExtentCanMatch($0.value.width, bounds.w, origin: bounds.x, scale: scale) && factorySnappedExtentCanMatch($0.value.height, bounds.h, origin: bounds.y, scale: scale) }
            .sorted { ($0.key.proposedWidth ?? .infinity) < ($1.key.proposedWidth ?? .infinity) }
        guard let chosen = candidates.first else { throw NSError(domain: "FactoryMeasuredRunGeometryMismatch", code: 1) }
        guard candidates.allSatisfy({ $0.value.width == chosen.value.width && $0.value.height == chosen.value.height && $0.value.lines == chosen.value.lines && $0.value.firstBaseline == chosen.value.firstBaseline }) else {
            throw NSError(domain: "FactoryAmbiguousMeasuredRun", code: 1)
        }
        print("FACTORY_RETAINED_RUN text=\(text) widthPX=\(chosen.value.width) heightPX=\(chosen.value.height) snappedWidthPX=\(bounds.w) lines=\(chosen.value.lineCount) proposedDIP=\(chosen.key.proposedWidth.map(String.init(describing:)) ?? "nil")")
        return chosen.value.run
    }
    func releaseAll() { retained.values.forEach { bridge.release($0.run) }; retained.removeAll() }
}
@MainActor final class RendererHost {
    let bridge: Bridge
    var graph: Graph?
    var window: BridgeWindow?
    var measurer: NativeMeasurer?
    var ownedHWND: HWND?
    var initialDPI: UInt32?
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
            let abi = try window.metrics()
            let owned = try factoryOwnedClient()
            let metrics = owned.size
            ownedHWND = owned.hwnd; initialDPI = metrics.dpi
            print("FACTORY_ABI_INITIAL_METRICS width=\(abi.width) height=\(abi.height) scale=\(abi.scale)")
            scale = metrics.scale
            viewport = Rect(x: 0, y: 0, w: Float(metrics.width), h: Float(metrics.height))
            let bodyFont = try factoryDefaultBodyFontPolicy(dpi: metrics.dpi)
            let nativeMeasurer = NativeMeasurer(bridge, scale, bodyFont)
            measurer = nativeMeasurer
            let graph = Graph(Witness_stack_overlay(), measurer: nativeMeasurer, scale: CGFloat(scale))
            graph.rootProposal = ProposedViewSize(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale))
            graph.commitSink = { [weak self] record in self?.commit(record) }
            self.graph = graph
            try window.requestTicks(true)
            graph.flush()
            print("FACTORY_RENDERER_READY scale=\(scale) width=\(metrics.width) height=\(metrics.height) hwnd=\(UInt(bitPattern: owned.hwnd)) pid=\(owned.pid) thread=\(owned.thread) dpi=\(metrics.dpi) metricsSource=owned-client-rect")
            fflush(stdout)
        } catch { fail(error) }
    }
    func fail(_ error: Error) { errors.append(String(describing: error)); bridge.requestQuit() }
    func commit(_ record: CommitRecord) {
        guard let root = record.root, let window else { return }
        let backgroundID = UInt64.max - 1
        var nodes: [NodeUpsert] = [NodeUpsert(id: backgroundID, bounds: viewport, primitives: [.rect(viewport, color: themeDark ? 0x1e1e1eff : 0xffffffff)])]
        let rootPixel = root.pixelFrame
        let rootBounds = Rect(x: Float(rootPixel.x), y: Float(rootPixel.y),
                              w: Float(rootPixel.width), h: Float(rootPixel.height))
        guard let centering = factoryCenteredRootSubtree(rootBounds, viewport: viewport) else {
            fail(NSError(domain: "FactoryRootCenteringMismatch", code: 1))
            return
        }
        print("FACTORY_ROOT_CENTERING rootX=\(rootBounds.x) rootY=\(rootBounds.y) rootW=\(rootBounds.w) rootH=\(rootBounds.h) dx=\(centering.dx) dy=\(centering.dy) viewportW=\(viewport.w) viewportH=\(viewport.h)")
        var current: Set<UInt64> = []
        let sharedMapper = FactorySharedNodeMapper(scale: scale) { text, font, bounds in
            guard let measurer = self.measurer else { throw NSError(domain: "FactoryMeasurerUnavailable", code: 1) }
            return try measurer.renderRun(text: text, font: font, bounds: bounds)
        }
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32) throws {
            let id = UInt64(n.instance + 1)
            current.insert(id)
            runtimeIDs[id] = n.id
            let p = n.pixelFrame
            let sourceBounds = Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height))
            let bounds = centering.applying(to: sourceBounds)
            let emission = try sharedMapper.emit(n, bounds: bounds)
            let primitives = emission.primitives
            let semantic = emission.semantic
            let flags = emission.flags
            if n.kind == "Rectangle" || n.kind == "Circle" {
                print("FACTORY_NATIVE_FILL node=\(n.id) kind=\(n.kind) x=\(bounds.x) y=\(bounds.y) width=\(bounds.w) height=\(bounds.h)")
            } else if n.kind == "Color" {
                print("FACTORY_NATIVE_COLOR node=\(n.id) x=\(bounds.x) y=\(bounds.y) width=\(bounds.w) height=\(bounds.h)")
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
    }
    func event(_ event: BridgeEvent) {
        if event.kind == .axAction, event.action == 1, let id = runtimeIDs[event.node] {
            _ = graph?.tapButton(id)
            graph?.flush()
        }
    }
    func tick(_ time: UInt64) {
        do {
            let owned = try factoryOwnedClient(expected: ownedHWND)
            guard owned.size.dpi == initialDPI else { throw NSError(domain: "FactoryDPIDriftUnsupported", code: 1) }
            let width = Float(owned.size.width), height = Float(owned.size.height)
            if viewport.w != width || viewport.h != height {
                viewport = Rect(x: 0, y: 0, w: width, h: height)
                graph?.rootProposal = ProposedViewSize(width: owned.size.logicalWidth, height: owned.size.logicalHeight)
                print("FACTORY_VIEWPORT_UPDATE width=\(owned.size.width) height=\(owned.size.height) dpi=\(owned.size.dpi) logicalWidth=\(owned.size.logicalWidth) logicalHeight=\(owned.size.logicalHeight)")
                fflush(stdout)
            }
        } catch { fail(error); return }
        if started == nil { started = time }
        graph?.tick(now: Double(time) / 1_000_000_000)
        graph?.flush()
        if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }
    }
}
let result: Int32 = MainActor.assumeIsolated {
    do {
        let bridge = try Bridge.load(path: "D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll")
        let host = RendererHost(bridge)
        bridge.onReady = { window in MainActor.assumeIsolated { host.ready(window) } }
        bridge.onEvent = { event in MainActor.assumeIsolated { host.event(event) } }
        bridge.onTick = { _, time in MainActor.assumeIsolated { host.tick(time) } }
        bridge.onWindowClosed = { MainActor.assumeIsolated {
            host.graph?.tearDown()
            host.measurer?.releaseAll()
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
