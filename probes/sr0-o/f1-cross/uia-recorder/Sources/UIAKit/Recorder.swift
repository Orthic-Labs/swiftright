#if os(Windows)
import Foundation
import CUIA

public struct RecorderOptions {
    public var pid: Int
    public var steps: FixtureSteps
    public var toolchain: String
    public var windowTimeout: Double = 30
    public init(pid: Int, steps: FixtureSteps, toolchain: String) { self.pid = pid; self.steps = steps; self.toolchain = toolchain }
}

public final class Recorder {
    let auto: Automation
    let opts: RecorderOptions
    var hwnd: UnsafeMutableRawPointer
    var root: UIAElement
    var closed = false

    public init(_ opts: RecorderOptions) throws {
        self.opts = opts
        auto = try Automation()
        let deadline = Date().addingTimeInterval(opts.windowTimeout)
        var h: UnsafeMutableRawPointer?
        repeat {
            h = cuia_find_window(UInt32(opts.pid))
            if h == nil { Thread.sleep(forTimeInterval: 0.25) }
        } while h == nil && Date() < deadline
        guard let h else { throw UIAError(what: "no visible top-level window for pid \(opts.pid) within \(opts.windowTimeout)s") }
        hwnd = h
        root = try auto.element(fromWindow: hwnd)
    }

    public func snapshotTree() -> UIANode { auto.walk(root) }

    private func ensureForeground() -> Bool {
        if cuia_foreground_pid() == UInt32(opts.pid) { return true }
        _ = cuia_activate(hwnd)
        Thread.sleep(forTimeInterval: 0.3)
        return cuia_foreground_pid() == UInt32(opts.pid)
    }

    private func resolve(_ s: Selector) throws -> UIAElement {
        let tree = auto.walk(root)
        let norm = WinNormalizer.normalize(tree)
        guard let n = Resolve.find(s, in: tree, ids: norm.idByIndex), let el = auto.handles[n.index] else {
            throw UIAError(what: "selector not found [\(s.summary)]")
        }
        return el
    }

    private func focus(_ el: UIAElement) throws {
        try el.setFocus()
        Thread.sleep(forTimeInterval: 0.15)
        guard el.hasFocus else { throw UIAError(what: "SetFocus returned but element lacks keyboard focus") }
    }

    private func perform(_ op: Op) throws -> String {
        switch op.op {
        case "wait":
            Thread.sleep(forTimeInterval: Double(op.ms ?? 0) / 1000)
            return "waited \(op.ms ?? 0) ms"
        case "resize":
            guard let w = op.width, let h = op.height else { throw UIAError(what: "resize needs width and height") }
            guard cuia_set_client_dip(hwnd, Int32(w), Int32(h)) == 1 else { throw UIAError(what: "MoveWindow failed") }
            return "resized \(w)x\(h) DIP"
        case "close":
            guard cuia_close_window(hwnd) == 1 else { throw UIAError(what: "PostMessage(WM_CLOSE) failed") }
            closed = true
            return "WM_CLOSE posted"
        case "touch":
            // Harness release signal: creates the file named by env SR0O_RELEASE_FLAG (read by the fixture's driver).
            guard let path = ProcessInfo.processInfo.environment["SR0O_RELEASE_FLAG"], !path.isEmpty else { throw UIAError(what: "touch: SR0O_RELEASE_FLAG not set") }
            guard FileManager.default.createFile(atPath: path, contents: Data("release\n".utf8)) else { throw UIAError(what: "touch: cannot create \(path)") }
            return "signalled"
        case "waitFor":
            guard let t = op.target else { throw UIAError(what: "waitFor needs target") }
            let deadline = Date().addingTimeInterval(Double(op.ms ?? 10000) / 1000)
            repeat {
                let tree = auto.walk(root)
                let norm = WinNormalizer.normalize(tree)
                let hit = Resolve.find(t, in: tree, ids: norm.idByIndex)
                if op.absent == true {
                    if hit == nil { return "absent" }
                } else if let n = hit, op.value == nil || n.value == op.value {
                    return "found"
                }
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < deadline
            throw UIAError(what: "waitFor timed out [\(t.summary)] value=\(op.value ?? "-")")
        case "focus":
            guard let t = op.target else { throw UIAError(what: "focus needs target") }
            try focus(try resolve(t))
            return "focused"
        case "invoke":
            guard let t = op.target else { throw UIAError(what: "invoke needs target") }
            try resolve(t).invoke()
            return "invoked"
        case "setValue":
            guard let t = op.target else { throw UIAError(what: "setValue needs target") }
            try resolve(t).setValue(op.value ?? "")
            return "value set"
        case "select":
            guard let t = op.target else { throw UIAError(what: "select needs target") }
            try resolve(t).selectRange(location: op.location ?? 0, length: op.length ?? 0)
            return "selected \(op.location ?? 0)+\(op.length ?? 0)"
        case "type", "key", "command":
            if let t = op.target { try focus(try resolve(t)) }
            if op.op == "type", ProcessInfo.processInfo.environment["SR0O_KEY_DELIVERY"] == "targeted" {
                try VKInput.typeTargeted(op.text ?? "", hwnd: hwnd)
                return "posted (window-targeted WM_CHAR)"
            }
            guard ensureForeground() else { throw UIAError(what: "target window is not foreground; refusing to send keys") }
            switch op.op {
            case "type": try VKInput.type(op.text ?? "")
            case "key": try VKInput.chord(op.text ?? "")
            default:
                guard let c = VKInput.commandChords[op.text ?? ""] else { throw UIAError(what: "unknown command \(op.text ?? "")") }
                try VKInput.chord(c)
            }
            return "sent"
        default:
            throw UIAError(what: "unknown op '\(op.op)'")
        }
    }

    /// Replays every step, observing after each. Returns the trace, the sidecar and whether all ops succeeded.
    public func run() -> (trace: WTrace, sidecar: Sidecar, ok: Bool) {
        var steps: [WStep] = []
        var observations: [WObservation] = []
        var extras: [StepExtra] = []
        var allOK = true

        for spec in opts.steps.steps {
            var results: [OpResult] = []
            let startNs = DispatchTime.now().uptimeNanoseconds
            for op in spec.ops {
                do {
                    let d = try perform(op)
                    results.append(OpResult(op: NativeMapping.describe([op]), ok: true, detail: d))
                } catch {
                    allOK = false
                    results.append(OpResult(op: NativeMapping.describe([op]), ok: false, detail: "\(error)"))
                    FileHandle.standardError.write(Data("step \(spec.id): \(error)\n".utf8))
                }
            }
            Thread.sleep(forTimeInterval: Double(spec.settleMs ?? 300) / 1000)
            steps.append(WStep(id: spec.id, logicalAction: spec.logicalAction,
                                   nativeMapping: NativeMapping.describe(spec.ops), timestamp: TraceAssembly.now()))
            var (obs, extra) = observe(spec, results: results)
            extra.monoStartNs = startNs
            extra.monoEndNs = DispatchTime.now().uptimeNanoseconds
            observations.append(obs)
            extras.append(extra)
        }

        let trace = WTrace(schemaVersion: "sr0-o.trace/v0", fixtureId: opts.steps.fixtureId, sourceHash: opts.steps.sourceHash,
                          platform: TraceAssembly.platform(toolchain: opts.toolchain), steps: steps, observations: observations,
                          declaredOrder: opts.steps.declaredOrder ?? [])
        let side = Sidecar(windowHandle: Int64(Int(bitPattern: hwnd)), pid: opts.pid, dpi: nil, steps: extras)
        return (trace, side, allOK)
    }

    private func observe(_ spec: StepSpec, results: [OpResult]) -> (WObservation, StepExtra) {
        if closed {
            // The window is gone (close op): nothing is observable. The sidecar tree is a bare window node.
            var extra = StepExtra(stepId: spec.id, opResults: results, tree: UIANode(index: 0, controlType: "Window"))
            extra.focusedAutomationId = nil
            return (WObservation(stepId: spec.id, model: [:], focusedNodeId: nil, selection: nil, lifecycle: [], effects: [], axNodes: nil), extra)
        }
        let tree = auto.walk(root)
        let norm = WinNormalizer.normalize(tree)
        var extra = StepExtra(stepId: spec.id, opResults: results, tree: tree)

        // Focused node: deepest node reporting keyboard focus.
        let focused = tree.flatten().last(where: { $0.hasFocus })
        var selection: WRange?
        if let f = focused {
            extra.focusedAutomationId = f.automationId
            extra.focusedControlType = f.controlType
            extra.focusedValue = f.value
            if let el = auto.handles[f.index], let st = el.textState() {
                selection = st.selection
                extra.selectionText = st.selectionText
                extra.caretRect = st.caretRect
            }
        }

        var model: [String: String] = [:]
        for (key, sel) in opts.steps.modelNodes ?? [:] {
            if let n = Resolve.find(sel, in: tree, ids: norm.idByIndex) { model[key] = n.value ?? n.name }
        }

        let obs = WObservation(stepId: spec.id, model: model, focusedNodeId: focused.flatMap { norm.idByIndex[$0.index] },
                              selection: selection, lifecycle: [], effects: [],
                              axNodes: spec.capture == true ? norm.nodes : nil)
        return (obs, extra)
    }
}
#endif
