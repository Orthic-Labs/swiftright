import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WinSDK

// Thread-local factory hook vetoes activation before staged renderer creates its window.
let factoryActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) { return 1 }
    return CallNextHookEx(nil, code, wParam, lParam)
}

func value(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

/// The pinned Tinos bytes. Registration with the renderer goes through the ABI 0.7 bridge entry
/// (`BundledFontLibrary` -> `swr_font_register`), not GDI: GDI AddFontResourceEx never reached GPUI's text system.
struct FactoryTinosResource {
    let path: String
    let resourceSHA256 = "sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61"
    let family = "Tinos"
    let postScriptName = "Tinos-Regular"
    /// Checks extension, size and SHA-256 before any byte reaches the renderer.
    func verify() throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "ttf", FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "FactoryTinosResourceUnavailable", code: 1)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber, bytes.int64Value == 521588 else {
            throw NSError(domain: "FactoryTinosResourceSizeMismatch", code: 1)
        }
        guard try FactorySHA256.hash(fileAt: url) == resourceSHA256 else {
            throw NSError(domain: "FactoryTinosResourceHashMismatch", code: 1)
        }
        print("FACTORY_TINOS_RESOURCE_VERIFIED path=\(url.path) resourceSHA256=\(resourceSHA256) bytes=\(bytes.int64Value)")
        fflush(stdout)
        return url
    }
}

/// Finds the bundled font: --tinos-font, else beside the exe, else the package Resources folder above it
/// (the exe lives under <package>/scratch/<triple>/release).
func factoryTinosFontPath() -> String {
    if let explicit = value("--tinos-font") { return explicit }
    let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    var dir = exeDir
    for _ in 0..<8 {
        for candidate in [dir.appendingPathComponent("Tinos-Regular.ttf"), dir.appendingPathComponent("Resources/Tinos-Regular.ttf")] {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        dir.deleteLastPathComponent()
    }
    return exeDir.appendingPathComponent("Tinos-Regular.ttf").path
}

struct FactoryTinosProviderMetricsInput {
    let lineHeightDIP: Float
    let ascentDIP: Float
    let descentDIP: Float
    let unitsPerEm: UInt16
    let ascentUnits: Int16
    let descentUnits: Int16
    let lineGapUnits: Int16
    let source: String
}

private struct FactoryTinosFontFileMetrics {
    let unitsPerEm: UInt16
    let ascentUnits: Int16
    let descentUnits: Int16
    let lineGapUnits: Int16

    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw NSError(domain: "FactoryTinosFontTableBounds", code: 1) }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    private static func i16(_ data: Data, _ offset: Int) throws -> Int16 { Int16(bitPattern: try u16(data, offset)) }
    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw NSError(domain: "FactoryTinosFontTableBounds", code: 1) }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
    private static func table(_ data: Data, _ tag: String) throws -> (offset: Int, length: Int) {
        guard tag.utf8.count == 4 else { throw NSError(domain: "FactoryTinosFontTagInvalid", code: 1) }
        let count = Int(try u16(data, 4))
        guard count <= 512, 12 + count * 16 <= data.count else { throw NSError(domain: "FactoryTinosFontDirectoryInvalid", code: 1) }
        let wanted = Array(tag.utf8)
        for index in 0..<count {
            let row = 12 + index * 16
            if Array(data[row..<(row + 4)]) == wanted {
                let offset = Int(try u32(data, row + 8))
                let length = Int(try u32(data, row + 12))
                guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset else { throw NSError(domain: "FactoryTinosFontTableBounds", code: 1) }
                return (offset, length)
            }
        }
        throw NSError(domain: "FactoryTinosFontTableMissing", code: 1, userInfo: [NSLocalizedDescriptionKey: tag])
    }
    static func read(path: String) throws -> FactoryTinosFontFileMetrics {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attrs[.size] as? NSNumber, bytes.int64Value > 0, bytes.int64Value <= 16 * 1024 * 1024 else { throw NSError(domain: "FactoryTinosFontSizeInvalid", code: 1) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let head = try table(data, "head")
        let hhea = try table(data, "hhea")
        guard head.length >= 20, hhea.length >= 10 else { throw NSError(domain: "FactoryTinosFontMetricsTableTooShort", code: 1) }
        let units = try u16(data, head.offset + 18)
        let ascent = try i16(data, hhea.offset + 4)
        let descent = try i16(data, hhea.offset + 6)
        let lineGap = try i16(data, hhea.offset + 8)
        guard units > 0, ascent > 0, descent != 0 else { throw NSError(domain: "FactoryTinosFontMetricsInvalid", code: 1) }
        return FactoryTinosFontFileMetrics(unitsPerEm: units, ascentUnits: ascent, descentUnits: descent, lineGapUnits: lineGap)
    }
}

private func validTinosMetric(_ raw: String?, key: String) throws -> Float? {
    guard let raw else { return nil }
    guard let metric = Float(raw), metric.isFinite, metric > 0, metric <= 256 else {
        throw NSError(domain: "FactoryTinosProviderMetricInvalid", code: 1, userInfo: [NSLocalizedDescriptionKey: key])
    }
    return metric
}

func tinosProviderMetrics(fontPath: String, pointSizeDIP: Float = 18) throws -> FactoryTinosProviderMetricsInput {
    let file = try FactoryTinosFontFileMetrics.read(path: fontPath)
    let units = Float(file.unitsPerEm)
    let ascentDefault = pointSizeDIP * Float(file.ascentUnits) / units
    let descentDefault = pointSizeDIP * abs(Float(file.descentUnits)) / units
    // SwiftUI/CoreText Text line height: round(ascent) + round(descent) in DIP; the hhea lineGap (leading) is not part of it (measured on macOS, ImageRenderer, Tinos 13/18/31 pt at 1x/2x/2.5x).
    let lineHeightDefault = ascentDefault.rounded() + descentDefault.rounded()
    guard ascentDefault.isFinite, descentDefault.isFinite, lineHeightDefault.isFinite, lineHeightDefault > 0 else { throw NSError(domain: "FactoryTinosFontMetricsInvalid", code: 1) }
    let lineHeight = try validTinosMetric(value("--tinos-line-height"), key: "--tinos-line-height") ?? lineHeightDefault
    let ascent = try validTinosMetric(value("--tinos-ascent"), key: "--tinos-ascent") ?? ascentDefault
    let descent = try validTinosMetric(value("--tinos-descent"), key: "--tinos-descent") ?? descentDefault
    let overrideSource = value("--tinos-line-height") != nil || value("--tinos-ascent") != nil || value("--tinos-descent") != nil
    print("FACTORY_TINOS_FONT_METRICS_SOURCE path=\(fontPath) source=ttf-head-hhea unitsPerEm=\(file.unitsPerEm) ascentUnits=\(file.ascentUnits) descentUnits=\(file.descentUnits) lineGapUnits=\(file.lineGapUnits) pointSizeDIP=\(pointSizeDIP) defaultsLineHeightDIP=\(lineHeightDefault) defaultsAscentDIP=\(ascentDefault) defaultsDescentDIP=\(descentDefault) overrides=\(overrideSource)")
    return FactoryTinosProviderMetricsInput(lineHeightDIP: lineHeight, ascentDIP: ascent, descentDIP: descent, unitsPerEm: file.unitsPerEm, ascentUnits: file.ascentUnits, descentUnits: file.descentUnits, lineGapUnits: file.lineGapUnits, source: overrideSource ? "ttf-head-hhea+cli-override" : "ttf-head-hhea")
}

@MainActor final class NativeMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    let resource: FactoryBundledFontResource
    let providerMetrics: FactoryTinosProviderMetricsInput
    var retained: [TextMeasureRequest: SwiftRightBridge.TextMeasurement] = [:]
    init(_ bridge: Bridge, _ scale: Float, resource: FactoryBundledFontResource, providerMetrics: FactoryTinosProviderMetricsInput) {
        self.bridge = bridge; self.scale = scale; self.resource = resource; self.providerMetrics = providerMetrics
    }
    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        do {
            guard Float(request.scale) == scale, request.fontID.hasPrefix("custom(Tinos-Regular,") else {
                throw NSError(domain: "FactoryUnsupportedMeasurementStyle", code: 1)
            }
            if let cached = retained[request] {
                return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(cached.width / scale), height: CGFloat(cached.height / scale)), baseline: CGFloat(cached.firstBaseline / scale), lineCount: cached.lineCount)
            }
            guard retained.count < 128 else { throw NSError(domain: "FactoryMeasurementCacheBound", code: 1) }
            let adapted = try factoryBundledMeasureRequest(request, resource: resource, resolve: { _, metadata in
                guard metadata.isCustom, metadata.familyName == resource.requestedFamily else { throw FactoryBundledFontAdapterError.familyMismatch }
                return FactoryBundledFontMetrics(lineHeightDIP: providerMetrics.lineHeightDIP, ascentDIP: providerMetrics.ascentDIP, descentDIP: providerMetrics.descentDIP)
            }, scale: scale)
            let result: SwiftRightBridge.TextMeasurement
            if request.lineLimit == 1 {
                let selection = try factorySelectSingleLineText(request.text,
                    maxWidth: adapted.request.maxWidth,
                    measure: { candidate in
                        var candidateRequest = adapted.request
                        candidateRequest.text = candidate
                        return try bridge.measure(candidateRequest)
                    },
                    release: { bridge.release($0) })
                result = selection.measurement
                print("FACTORY_TINOS_SINGLE_LINE originalUTF8=\(request.text.utf8.count) displayUTF8=\(selection.displayText.utf8.count) candidateCount=\(selection.candidateCount) maxWidthPX=\(adapted.request.maxWidth)")
            } else {
                result = try bridge.measure(adapted.request)
            }
            retained[request] = result
            print("FACTORY_TINOS_MEASURE text=\(request.text) requestedFamily=\(resource.requestedFamily) family=\(adapted.request.fontFamily) fontSize=\(adapted.request.fontSize) lineHeight=\(adapted.request.lineHeight) providerFamily=\(resource.providerFamily) resourceSHA256=\(resource.resourceSHA256) widthPX=\(result.width) heightPX=\(result.height) lines=\(result.lineCount) lineLimit=\(request.lineLimit.map(String.init) ?? "nil")")
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(result.width / scale), height: CGFloat(result.height / scale)), baseline: CGFloat(result.firstBaseline / scale), lineCount: result.lineCount)
        } catch { fatalError("Native Tinos measurement failed: \(error)") }
    }
    func renderRun(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        let candidates = retained.filter { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale && $0.key.lineLimit == 1 && factorySnappedExtentCanMatch($0.value.width, bounds.w, origin: bounds.x, scale: scale) && factorySnappedExtentCanMatch($0.value.height, bounds.h, origin: bounds.y, scale: scale) }.sorted { ($0.key.proposedWidth ?? .infinity) < ($1.key.proposedWidth ?? .infinity) }
        guard let chosen = candidates.first else { throw NSError(domain: "FactoryMeasuredRunGeometryMismatch", code: 1) }
        guard candidates.allSatisfy({ $0.value.width == chosen.value.width && $0.value.height == chosen.value.height && $0.value.lines == chosen.value.lines && $0.value.firstBaseline == chosen.value.firstBaseline }) else { throw NSError(domain: "FactoryAmbiguousMeasuredRun", code: 1) }
        print("FACTORY_TINOS_RETAINED_RUN text=\(text) widthPX=\(chosen.value.width) heightPX=\(chosen.value.height) lines=\(chosen.value.lineCount) providerFamily=Tinos")
        return chosen.value.run
    }
    func releaseAll() { retained.values.forEach { bridge.release($0.run) }; retained.removeAll() }
}
func factoryResolvedFill(_ value: ResolvedColor, opacity: Double) throws -> UInt32 {
    switch value {
    case .rgba(let r,let g,let b,let a): return try factoryRGBAFill([r,g,b,a],opacity:opacity)
    case .semantic(let name):
        guard opacity.isFinite, opacity >= 0, opacity <= 1 else { throw NSError(domain:"FactoryInvalidFillOpacity",code:1) }
        let raw=try factorySemanticFill(name)
        return (raw & 0xffffff00) | UInt32((Double(raw & 255)*opacity).rounded())
    }
}
@MainActor final class RendererHost {
    let bridge: Bridge
    var graph: Graph?
    var window: BridgeWindow?
    var measurer: NativeMeasurer?
    let tinos: FactoryTinosResource
    var resource: FactoryBundledFontResource?
    let providerMetrics: FactoryTinosProviderMetricsInput
    var ownedHWND: HWND?
    var initialDPI: UInt32?
    let themeDark = false
    var viewport = Rect(x: 0, y: 0, w: 320, h: 240)
    var scale: Float = 1
    var version: UInt64 = 0
    var started: UInt64?
    var live: Set<UInt64> = []
    var runtimeIDs: [UInt64: String] = [:]
    var errors: [String] = []
    init(_ bridge: Bridge, tinos: FactoryTinosResource,
         providerMetrics: FactoryTinosProviderMetricsInput) {
        self.bridge = bridge
        self.tinos = tinos
        self.providerMetrics = providerMetrics
    }
    /// Registers the bundled bytes with the renderer before the first measurement, then proves the family now
    /// resolves to those bytes (and that an unregistered family still reports fallback).
    func registerBundledFont() throws -> FactoryBundledFontResource {
        let url = try tinos.verify()
        let before = try bridge.resolveFont(family: tinos.family)
        let unknown = try bridge.resolveFont(family: "SwiftRightNoSuchFamily")
        guard before.source == .fallback, unknown.source == .fallback else {
            throw NSError(domain: "FactoryTinosAlreadyResolvable", code: 1, userInfo: [NSLocalizedDescriptionKey: "before=\(before.source) unknown=\(unknown.source)"])
        }
        let library = BundledFontLibrary(bridge: bridge)
        let reg = try library.register(file: url)
        let after = try bridge.resolveFont(family: tinos.family)
        let afterUnknown = try bridge.resolveFont(family: "SwiftRightNoSuchFamily")
        guard reg.family == tinos.family, "sha256:" + reg.sha256Hex == tinos.resourceSHA256,
              after.source == .bundled, after.handle == reg.handle, after.sha256 == reg.sha256,
              afterUnknown.source == .fallback,
              let provider = library.providerFamily(forCustomName: tinos.postScriptName) else {
            throw NSError(domain: "FactoryTinosRegistrationMismatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "reg=\(reg) after=\(after)"])
        }
        print("FACTORY_TINOS_FONT_REGISTERED path=\(url.path) scope=renderer-process abi=\(bridge.revision) handle=\(reg.handle) flags=\(reg.flags.rawValue) resourceSHA256=sha256:\(reg.sha256Hex) family=\(reg.family) weight=\(reg.weight) faces=\(reg.faceCount) providerFamily=\(provider) resolveBefore=\(before.source) resolveAfter=\(after.source) resolveUnknownBefore=\(unknown.source) resolveUnknownAfter=\(afterUnknown.source) rendererSelection=bundled-bytes")
        fflush(stdout)
        return FactoryBundledFontResource(requestedFamily: tinos.postScriptName, providerFamily: provider, postScriptName: tinos.postScriptName, resourceSHA256: tinos.resourceSHA256, path: url.path)
    }
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
            let resource = try registerBundledFont()
            self.resource = resource
            let nativeMeasurer = NativeMeasurer(bridge, scale, resource: resource, providerMetrics: providerMetrics)
            measurer = nativeMeasurer
            let graph = Graph(Witness_tinos_bundled_text_pilot(), measurer: nativeMeasurer, scale: CGFloat(scale))
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
                    guard n.style.foreground == nil, n.opacity == 1 else { throw NSError(domain: "FactoryUnsupportedTextPaintStyle", code: 1) }
                    guard let measurer else { throw NSError(domain: "FactoryMeasurerUnavailable", code: 1) }
                    let retainedRun = try measurer.renderRun(text: text, font: n.style.font, bounds: bounds)
                    primitives = [.text(retainedRun, x: bounds.x, y: bounds.y)]
                    semantic = SemanticNode(role: .staticText, label: text, identifier: n.id, disabled: !n.accessibility.isEnabled)
                }
            case "Button":
                let enabled = n.accessibility.isEnabled
                primitives = [.rect(bounds, color: enabled ? 0x2563ebff : 0xaaaaaaff, radius: 6 * scale)]
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .button, label: n.accessibility.label ?? n.children.first?.text ?? "",
                  actions: enabled ? [.invoke, .focus] : [], identifier: n.id, disabled: !enabled)
            case "Rectangle", "Circle":
                guard let shape=n.shape, let paint=shape.paint, paint.kind == .fill else { throw NSError(domain:"FactoryShapeFillMetadataRequired",code:1) }
                let kind: FactoryFillGeometry
                switch shape.geometry {
                case .rectangle: kind = .rectangle
                case .circle: kind = .circle
                default: throw NSError(domain:"FactoryUnsupportedShapeGeometry",code:1)
                }
                let fill=try factoryFillRect(kind,x:bounds.x,y:bounds.y,width:bounds.w,height:bounds.h)
                primitives=[.rect(Rect(x:fill.x,y:fill.y,w:fill.width,h:fill.height),color:try factoryResolvedFill(paint.color,opacity:n.opacity),radius:fill.radius)]
                print("FACTORY_NATIVE_FILL node=\(n.id) kind=\(n.kind) x=\(fill.x) y=\(fill.y) width=\(fill.width) height=\(fill.height) radius=\(fill.radius)")
            case "Color":
                guard let color=n.color else { throw NSError(domain:"FactoryColorMetadataRequired",code:1) }
                primitives=[.rect(bounds,color:try factoryResolvedFill(color,opacity:n.opacity))]
                print("FACTORY_NATIVE_COLOR node=\(n.id) x=\(bounds.x) y=\(bounds.y) width=\(bounds.w) height=\(bounds.h)")
            case let kind where factoryIsStructuralContainer(kind): break
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
        let fontPath = factoryTinosFontPath()
        let providerMetrics = try tinosProviderMetrics(fontPath: fontPath)
        let tinos = FactoryTinosResource(path: fontPath)
        print("FACTORY_TINOS_PROVIDER_METRICS lineHeightDIP=\(providerMetrics.lineHeightDIP) ascentDIP=\(providerMetrics.ascentDIP) descentDIP=\(providerMetrics.descentDIP) unitsPerEm=\(providerMetrics.unitsPerEm) ascentUnits=\(providerMetrics.ascentUnits) descentUnits=\(providerMetrics.descentUnits) lineGapUnits=\(providerMetrics.lineGapUnits) source=\(providerMetrics.source) family=Tinos postScriptName=Tinos-Regular resourceSHA256=\(tinos.resourceSHA256)")
        fflush(stdout)
        // ABI 0.7 renderer (font registration); the pinned 0.6 renderer under inputs\\renderer is not touched.
        let bridge = try Bridge.load(path: "D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer-0.7\\swiftright_render.dll", minimumRevision: .v07)
        print("FACTORY_ABI revision=\(bridge.revision) minor=\(bridge.info.abi_minor) fnCount=\(bridge.info.fn_count) fonts=\(bridge.supportsFontRegistration)")
        let host = RendererHost(bridge, tinos: tinos, providerMetrics: providerMetrics)
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
