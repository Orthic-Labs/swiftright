import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WinSDK

// Thread-local factory hook vetoes activation before staged renderer creates its window.
let factoryActivationVeto: HOOKPROC = { code, wParam, lParam in
    if code == Int32(HCBT_ACTIVATE) || code == Int32(HCBT_SETFOCUS) { return 1 }
    return CallNextHookEx(nil, code, wParam, lParam)
}

// Factory Windows palette: explicit semantic-name policy, never sampled Mac expected pixels.
func factoryColor(_ value: ResolvedColor?, dark: Bool, opacity: Double = 1) throws -> UInt32 {
    let color: UInt32
    switch value {
    case .rgba(let r, let g, let b, let a):
        func byte(_ v: Double) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        color = (byte(r) << 24) | (byte(g) << 16) | (byte(b) << 8) | byte(a)
    case .semantic(let name):
        let palette: [String: UInt32] = ["label": dark ? 0xffffffff : 0x1f1f1fff,
          "secondaryLabel": dark ? 0xbfbfbfff : 0x666666ff, "system.red": 0xff3b30ff,
          "system.orange": 0xff9500ff, "system.yellow": 0xffcc00ff, "system.green": 0x34c759ff,
          "system.blue": 0x007affff, "system.purple": 0xaf52deff, "system.pink": 0xff2d55ff,
          "system.gray": 0x8e8e93ff, "black": 0x000000ff, "white": 0xffffffff, "clear": 0]
        guard let c = palette[name] else { throw NSError(domain: "FactoryUnknownSemanticColor", code: 1, userInfo: [NSLocalizedDescriptionKey:name]) }
        color = c
    case nil: color = dark ? 0xffffffff : 0x1f1f1fff
    }
    let alpha = UInt32((Double(color & 255) * min(1, max(0, opacity))).rounded())
    return (color & 0xffffff00) | alpha
}
struct FactoryFont { let family: String; let size: Float; let weight: UInt32; var lineHeight: Float { size * 1.5 } }
func factoryFont(_ id: String, _ metadata: Font.Metadata?) throws -> FactoryFont {
    var size: Float = 16, weight: UInt32 = 400, family = "Segoe UI"
    if id.hasPrefix("system("), let tail = id.split(separator:"(").dropFirst().first {
        let fields = tail.split(separator:")")[0].split(separator:",")
        if let first = fields.first, let value = Float(first) { size = value }
        if fields.count > 1 { weight = ["regular":400,"medium":500,"semibold":600,"bold":700][String(fields[1])] ?? 400 }
    } else if id.hasPrefix("textStyle.") {
        size = ["textStyle.largeTitle":34,"textStyle.title":28,"textStyle.title2":22,"textStyle.title3":20,
          "textStyle.headline":17,"textStyle.subheadline":15,"textStyle.body":17,"textStyle.callout":16,
          "textStyle.footnote":13,"textStyle.caption":12,"textStyle.caption2":11][id] ?? 16
    }
    if let m = metadata {
        if m.isCustom { throw NSError(domain:"FactoryABIPrivateFontCollectionUnavailable",code:1,userInfo:[NSLocalizedDescriptionKey:m.familyName ?? id]) }
        if let value = m.pointSize { size = Float(value) }
        if let value = m.weight { weight = ["regular":400,"medium":500,"semibold":600,"bold":700][value.rawValue] ?? 400 }
        if let value = m.familyName { family = value }
        switch m.design {
        case .serif?: family = "Cambria"
        case .monospaced?: family = "Consolas"
        case .rounded?:
            // Explicit installed native rounded family, never substitute a default font.
            let path = "C:\\Windows\\Fonts\\ARLRDBD.TTF"
            guard FileManager.default.fileExists(atPath:path) else { throw NSError(domain:"FactoryRoundedFontProviderUnavailable",code:1) }
            family = "Arial Rounded MT Bold"
        case .default?, nil: break
        }
    }
    return FactoryFont(family:family,size:size,weight:weight)
}
struct FactoryImageAsset: Decodable { let identity: String; let width: UInt32; let height: UInt32; let rgbaBase64: String }
func factoryImage(_ reference: ImageReference, bridge: Bridge) throws -> (ImageHandle, Float, Float) {
    let identity: String
    switch reference { case .system(let name): identity = "system:" + name; case .named(let name): identity = "named:" + name }
    let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("FactoryImageAssets.json")
    guard FileManager.default.fileExists(atPath:url.path) else { throw NSError(domain:"FactorySourceImageAssetUnavailable",code:1,userInfo:[NSLocalizedDescriptionKey:identity]) }
    let assets = try JSONDecoder().decode([FactoryImageAsset].self, from:Data(contentsOf:url))
    guard let asset = assets.first(where:{$0.identity == identity}), asset.width > 0, asset.height > 0, asset.width <= 4096, asset.height <= 4096, let data = Data(base64Encoded:asset.rgbaBase64),
          UInt64(asset.width)*UInt64(asset.height)*4 == UInt64(data.count) else { throw NSError(domain:"FactorySourceImageAssetUnavailable",code:1,userInfo:[NSLocalizedDescriptionKey:identity]) }
    return (try bridge.registerImage(width:asset.width,height:asset.height,rgba:Array(data)), Float(asset.width), Float(asset.height))
}

@MainActor final class NativeMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    init(_ bridge: Bridge, _ scale: Float) { self.bridge = bridge; self.scale = scale }
    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        do {
            let font = try factoryFont(request.fontID,request.fontMetadata)
            let result = try bridge.measure(MeasureRequest(text: request.text, fontFamily: font.family, weight:font.weight,
              fontSize: font.size, lineHeight: font.lineHeight, scale: scale,
              maxWidth: Float(request.proposedWidth ?? 0) * scale))
            bridge.release(result.run)
            let lines = request.lineLimit.map { min(result.lineCount,$0) } ?? result.lineCount
            let height = request.lineLimit.map { min(result.height/scale,Float($0)*font.lineHeight) } ?? result.height/scale
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(result.width / scale),
              height: CGFloat(height)), baseline: CGFloat(result.firstBaseline / scale), lineCount:lines)
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
            let graph = Graph(Witness_scroll_view(), measurer: NativeMeasurer(bridge, scale), scale: CGFloat(scale))
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
        var images: [ImageHandle] = []
        var current: Set<UInt64> = []
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32, clip: Rect? = nil) throws {
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
                    let font = try factoryFont(n.style.font?.id ?? "",n.style.font?.metadata)
                    let measured = try bridge.measure(MeasureRequest(text: text,fontFamily:font.family,weight:font.weight,color:try factoryColor(n.style.foreground,dark:themeDark,opacity:n.opacity),fontSize:font.size,
                      lineHeight:font.lineHeight,scale:scale,maxWidth:bounds.w))
                    runs.append(measured.run)
                    primitives = [.clipPush(bounds), .text(measured.run, x: bounds.x, y: bounds.y), .clipPop]
                    semantic = SemanticNode(role: .staticText, label: text, identifier: n.id, disabled: !n.accessibility.isEnabled)
                }
            case "Button":
                let enabled = n.accessibility.isEnabled
                primitives = [.rect(bounds, color: enabled ? 0x2563ebff : 0xaaaaaaff, radius: 6 * scale)]
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .button, label: n.accessibility.label ?? n.children.first?.text ?? "",
                  actions: enabled ? [.invoke, .focus] : [], identifier: n.id, disabled: !enabled)
            case "Rectangle", "RoundedRectangle", "Circle":
                guard let shape = n.shape else { throw NSError(domain:"FactoryMissingShapeMetadata",code:1) }
                let color = try factoryColor(shape.paint?.color ?? n.style.foreground,dark:themeDark,opacity:n.opacity)
                var rect = bounds
                let radius: Float
                switch shape.geometry {
                case .rectangle: radius = 0
                case .roundedRectangle(let corner,let style):
                    guard style == .circular else { throw NSError(domain:"FactoryABIContinuousCornerUnavailable",code:1) }
                    radius = Float(corner) * scale
                case .circle:
                    let diameter = min(bounds.w,bounds.h)
                    rect = Rect(x:bounds.x+(bounds.w-diameter)/2,y:bounds.y+(bounds.h-diameter)/2,w:diameter,h:diameter)
                    radius = diameter/2
                }
                if shape.paint?.kind == .stroke {
                    let width = Float(shape.paint?.lineWidth ?? 1)*scale
                    // ABI border is inside its rect; expand by half-width for centered Swift stroke.
                    rect = Rect(x:rect.x-width/2,y:rect.y-width/2,w:rect.w+width,h:rect.h+width)
                    primitives = [.rect(rect,color:0,radius:radius+width/2,borderColor:color,borderWidth:width)]
                } else { primitives = [.rect(rect,color:color,radius:radius)] }
            case "Image":
                guard let reference = n.image, let sizing = n.imageSizing else { throw NSError(domain:"FactoryMissingImageReference",code:1) }
                guard sizing.resizingMode == .stretch,
                      sizing.capInsets.top == 0, sizing.capInsets.bottom == 0,
                      sizing.capInsets.leading == 0, sizing.capInsets.trailing == 0 else {
                    throw NSError(domain:"FactoryABIImageTileOrCapInsetsUnavailable",code:1)
                }
                if case .system("star.fill") = reference {
                    // Native Windows system-symbol policy; Microsoft FavoriteStarFill E735.
                    // https://learn.microsoft.com/en-us/windows/apps/design/iconography/segoe-fluent-icons-font
                    let size = min(bounds.w,bounds.h)/scale
                    let measured = try bridge.measure(MeasureRequest(text:"\u{e735}",fontFamily:"Segoe Fluent Icons",
                      color:try factoryColor(n.style.foreground,dark:themeDark,opacity:n.opacity),fontSize:size,lineHeight:size,scale:scale,maxWidth:bounds.w))
                    runs.append(measured.run)
                    primitives = [.text(measured.run,x:bounds.x+(bounds.w-measured.width)/2,y:bounds.y+(bounds.h-measured.height)/2)]
                    print("FACTORY_SYSTEM_IMAGE identity=star.fill provider=Segoe_Fluent_Icons glyph=E735")
                } else {
                    let (image, naturalWidth, naturalHeight) = try factoryImage(reference,bridge:bridge);images.append(image)
                    var imageBounds = bounds
                    if sizing.scalesToFit {
                        let factor = min(bounds.w/naturalWidth,bounds.h/naturalHeight)
                        let width = naturalWidth*factor, height = naturalHeight*factor
                        imageBounds = Rect(x:bounds.x+(bounds.w-width)/2,y:bounds.y+(bounds.h-height)/2,w:width,h:height)
                    }
                    primitives = [.image(image,imageBounds)]
                }
                semantic = SemanticNode(role:.image,label:n.accessibility.label ?? reference.name,identifier:n.id)
            case "Toggle":
                let enabled = n.accessibility.isEnabled
                let checked = n.accessibility.value == "1"
                let box = Rect(x:bounds.x,y:bounds.y,w:18*scale,h:18*scale)
                primitives = [.rect(box,color:checked ? 0x007affff : 0xffffffff,radius:3*scale,borderColor:0x8e8e93ff,borderWidth:scale)]
                flags = [.hitTarget,.focusable]
                semantic = SemanticNode(role:.checkbox,label:n.accessibility.label ?? "",actions:enabled ? [.invoke,.focus] : [],identifier:n.id,toggled:checked ? .on : .off,disabled:!enabled)
            case "ScrollView":
                // Runtime snapshot already resolves child offsets; clip child primitives to its native viewport.
                primitives = []
                semantic = SemanticNode(role:.group,label:n.accessibility.label ?? "",identifier:n.id)
            case "VStack", "HStack", "ZStack", "Layout", "Group", "EmptyView", "Spacer": break
            default:
                if !n.kind.hasPrefix("modifier.") && !n.kind.hasPrefix("Witness_") && n.kind != "Root" && n.kind != "Witness_scroll_view" {
                    throw NSError(domain: "FactoryRendererUnsupportedNode", code: 1, userInfo: [NSLocalizedDescriptionKey: n.kind])
                }
            }
            if let clip, !primitives.isEmpty { primitives = [.clipPush(clip)] + primitives + [.clipPop] }
            nodes.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds, primitives: primitives, semantic: semantic))
            var childClip = clip
            if n.kind == "ScrollView" {
                if let clip {
                    let x = max(clip.x,bounds.x), y = max(clip.y,bounds.y)
                    childClip = Rect(x:x,y:y,w:max(0,min(clip.x+clip.w,bounds.x+bounds.w)-x),h:max(0,min(clip.y+clip.h,bounds.y+bounds.h)-y))
                } else { childClip = bounds }
            }
            for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index), clip:childClip) }
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
        images.forEach { bridge.release($0) }
    }
    func event(_ event: BridgeEvent) {
        if event.kind == .axAction, event.action == 1, let id = runtimeIDs[event.node] {
            if graph?.activateToggle(id) != true { _ = graph?.tapButton(id) }
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
        let bridge = try Bridge.load(path: "D:\\Claude\\sr0-r10\\renderer\\swiftright_render.dll")
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
