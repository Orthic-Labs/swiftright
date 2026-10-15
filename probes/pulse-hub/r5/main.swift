import Foundation
import SwiftRightHost
import WinSDK
import SwiftUI
import PulseHub
import PulseHubFixtures
import RightKitHub
import RightKitHubQA

// Frame k of the capture job (env SWIFTRIGHT_FRAME) = section k/2, light for even k and dark for odd k.
let hubFrame: Int = {
    if let e = ProcessInfo.processInfo.environment["SWIFTRIGHT_FRAME"], let n = Int(e) { return n }
    // interact job: no per-run env, so a counter file beside the exe numbers the launches 0, 1, 2, ...
    let url = URL(fileURLWithPath: "C:\\work\\hub-frame.txt")   // set by a Sandbox `command` job before the interact job
    print("HOST_FRAME_FILE \(url.path) exists=\(FileManager.default.fileExists(atPath: url.path))"); fflush(stdout)
    let n = Int((try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    try? String(n + 1).write(to: url, atomically: true, encoding: .utf8)
    return n
}()
let hubDark = hubFrame % 2 == 1

// Capture host: an owned renderer window of a fixed client size, the witness as a plain SwiftUI-source view, and the PRODUCT paint
// path (SwiftRightHost: shapes incl. continuous, Image(systemName:), body/custom fonts, line limit). Nothing here paints:
// the host only places the resolved tree (optionally centred in the viewport), draws the white/dark background, commits it
// and owns the capture lifecycle (activation veto, owned-window metrics, 10 s lease).
// Probe copy (probes/pulse-hub/host) of the alert case host, with the Pulse hub as the root view and no dialog coordinator. Original stamp: blocks-17-20/new-case.py (a copy of the shared host with the dialog coordinator): presented alerts and confirmation dialogs open as
// SWR_MODAL_DIALOG task dialogs and their answers route back to the graph (PresentationCoordinator, SwiftRightHost). The TaskDialog is this process's own window
// and takes the foreground inside the Sandbox, so the owned-foreground abort of FactoryViewport.swift is off here; the capture lease follows
// --factory-capture-lease-seconds=N (default 10).
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
    static let dark = hubDark
    var rootView: AnyView = AnyView(EmptyView())

    let bridge: Bridge
    var graph: Graph?
    var window: BridgeWindow?
    var measurer: BridgeTextMeasurer?
    var systemImages: SystemImageRegistry?
    var painter: ResolvedNodePainter?
    var ownedHWND: HWND?
    var initialDPI: UInt32?
    var viewport = Rect(x: 0, y: 0, w: 900, h: 600)
    var scale: Float = 1
    var version: UInt64 = 0
    var started: UInt64?
    var live: Set<UInt64> = []
    var runtimeIDs: [UInt64: String] = [:]
    var errors: [String] = []
    // The bridge drains late main-queue work after onWindowClosed; no window ownership lookup is valid then.
    var windowClosed = false
    static let leaseNS: UInt64 = {
        for a in CommandLine.arguments where a.hasPrefix("--factory-capture-lease-seconds=") { if let n = UInt64(a.dropFirst("--factory-capture-lease-seconds=".count)), n > 0 { return n * 1_000_000_000 } }
        return 10_000_000_000
    }()
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
            // The hub's view comes from an async load (preparedView), so the graph starts once it is ready, on the main actor inside the
            // renderer's message loop. (A top-level await in main would make COM MTA and the renderer's OleInitialize fail.)
            let startupScale = scale, startupMetrics = metrics
            Task { @MainActor [weak self] in
                let t0 = Date()
                guard let self, !self.windowClosed else { return }
                let root = await makeHubRoot(frame: hubFrame)
                print("HOST_HUB_LOADED seconds=\(Date().timeIntervalSince(t0))"); fflush(stdout)
                print("HOST_GRAPH_INIT"); fflush(stdout)
                let graph = Graph(root, measurer: measurer, scale: CGFloat(startupScale))
                print("HOST_GRAPH_CREATED"); fflush(stdout)
                images.install(on: graph)
                graph.rootProposal = ProposedViewSize(width: CGFloat(startupMetrics.width) / CGFloat(startupScale), height: CGFloat(startupMetrics.height) / CGFloat(startupScale))
                graph.commitSink = { [weak self] record in self?.commit(record) }
                self.graph = graph
                let t1 = Date()
                graph.flush()
                print("HOST_GRAPH_FLUSHED seconds=\(Date().timeIntervalSince(t1))"); fflush(stdout)
            }
            try window.requestTicks(true)
            print("HOST_RENDERER_READY scale=\(scale) width=\(metrics.width) height=\(metrics.height) hwnd=\(UInt(bitPattern: owned.hwnd)) pid=\(owned.pid) thread=\(owned.thread) dpi=\(metrics.dpi) metricsSource=owned-client-rect")
            fflush(stdout)
        } catch { fail(error) }
    }

    func fail(_ error: Error) { errors.append(String(describing: error)); bridge.requestQuit() }

    func commit(_ record: CommitRecord) {
        guard !windowClosed, let root = record.root, let window, let painter else { return }
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
                                               place: { placement.applying(to: $0) }) { txIn in
                var tx = txIn
                // round 5: no probe filter here; the transparent hit areas are the product's to handle (they were opaque black before block 31)
                let prims = tx.upserts.reduce(0) { $0 + $1.primitives.count }
                let images = tx.upserts.reduce(0) { n, u in n + u.primitives.filter { if case .image = $0 { return true } else { return false } }.count }
                let ident = tx.upserts.compactMap { $0.semantic?.identifier.utf8.count }.max() ?? 0
                var faint = 0, black = 0
                for u in tx.upserts { for pr in u.primitives { if case .rect(_, let c, _, _, _) = pr { if c & 0xff <= 2 { faint += 1 }; if c == 0x000000ff { black += 1; if black <= 3 { print("HOST_BLACK_RECT node=\(u.id) parent=\(u.parent) bounds=\(u.bounds) ident=\(u.semantic?.identifier.suffix(120) ?? "-")") } } } } }
                print("HOST_TX_RECTS faintAlpha=\(faint) opaqueBlack=\(black)")
                print("HOST_TX upserts=\(tx.upserts.count) removes=\(tx.removes.count) primitives=\(prims) imagePrimitives=\(images) maxIdentifierBytes=\(ident)"); fflush(stdout)
                try window.commit(tx) }
            version += 1
            live = committed.live
            runtimeIDs.merge(committed.runtimeIDs) { _, new in new }
            print("HOST_COMMIT version=\(version) nodes=\(committed.nodeCount)")
            fflush(stdout)
        } catch { fail(error) }
    }

    func event(_ event: BridgeEvent) {
        guard !windowClosed else { return }
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
        graph?.tick(now: Double(time) / 1_000_000_000)
        graph?.flush()
        if time - (started ?? time) > Self.leaseNS { bridge.requestQuit() }
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

// Probe diagnostics: say which exception ends the process (a Swift trap is 0xC000001D or 0x80000003, a stack overflow 0xC00000FD).
let hubExceptionHandler: PVECTORED_EXCEPTION_HANDLER = { info in
    let code = info?.pointee.ExceptionRecord.pointee.ExceptionCode ?? 0
    if code == 0xC00000FD || code == 0xC0000005 || code == 0xC000001D || code == 0x80000003 || code == 0xC0000409 {
        let addr = UInt(bitPattern: info?.pointee.ExceptionRecord.pointee.ExceptionAddress)
        print("HOST_MODULE_BASE 0x\(String(UInt(bitPattern: GetModuleHandleW(nil)), radix: 16))"); print("HOST_EXCEPTION code=0x\(String(UInt32(bitPattern: Int32(bitPattern: UInt32(code))), radix: 16)) address=0x\(String(addr, radix: 16))"); fflush(stdout)
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 200)
        let n = RtlCaptureStackBackTrace(0, 200, &frames, nil)
        print("HOST_EXCEPTION_FRAMES " + frames.prefix(Int(n)).map { "0x" + String(UInt(bitPattern: $0), radix: 16) }.joined(separator: " ")); fflush(stdout)
    }
    return 0
}
print("HOST_COLOR_TEST \(Color.black.opacity(0.001).resolvedColor) clear=\(Color.clear.resolvedColor)"); fflush(stdout)
var hubGuarantee: ULONG = 262144   // room for the handler to run after a stack overflow
_ = SetThreadStackGuarantee(&hubGuarantee)
_ = AddVectoredExceptionHandler(1, hubExceptionHandler)

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
        try bridge.run(title: "Alchemist FactoryProbe", width: 900, height: 600)
        host.errors.forEach { print("HOST_RENDER_ERROR \($0)") }
        return host.errors.isEmpty ? 0 : 1
    } catch { print("HOST_STARTUP_ERROR \(error)"); return 78 }
}
fflush(stdout)
exit(result)
