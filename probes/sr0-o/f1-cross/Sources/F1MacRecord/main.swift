import AppKit
import ApplicationServices
import Foundation

// F1MacRecord: launches a fixture (non-self-test mode), drives it with a logical step file through AX and
// CGEvent.postToPid (never the global HID tap), and dumps raw per-step observations for F1Assemble.
//   F1MacRecord --fixture <FixtureApp binary> --events <jsonl path> --out <raw json> --steps <steps-mac json>
// steps-mac json: {"launchArgs": [..FixtureApp flags..], "steps": [{"id","logicalAction","settleMs","ops":[..]}]}
// ops: focus{id} | type{text,expectId?,expectValue?} | stdin{json} | press{id | afterId+title} | setValue{id,value} |
//      waitNode{id,absent?,ms?} | waitValue{id,value,ms?} | waitEvent{contains,ms?} | wait{ms}
// Fixture stdin carries the fake-engine release (the fixture's driver protocol). Exit: 0 ok, 1 a step failed, 2 setup error.

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func argValue(_ n: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
    return a[i + 1]
}
guard let fixtureBin = argValue("--fixture"), let eventsPath = argValue("--events"), let outPath = argValue("--out"),
      let stepsPath = argValue("--steps") else {
    eprint("usage: F1MacRecord --fixture <FixtureApp> --events <jsonl> --out <raw.json> --steps <steps-mac.json>")
    exit(2)
}
guard let plan = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: stepsPath)))) as? [String: Any],
      let planSteps = plan["steps"] as? [[String: Any]] else { eprint("cannot read steps file \(stepsPath)"); exit(2) }
let launchArgs = plan["launchArgs"] as? [String] ?? ["--fixture", "F1"]
guard AXIsProcessTrusted() else {
    eprint("BLOCKER: Accessibility permission missing for \(Bundle.main.executablePath ?? CommandLine.arguments[0])")
    exit(2)
}

// MARK: AX helpers

func axAttr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
    return v as AnyObject
}
func axString(_ el: AXUIElement, _ name: String) -> String? { axAttr(el, name) as? String }
func axActions(_ el: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(el, &names) == .success, let names else { return [] }
    return (names as? [String]) ?? []
}
func axSettable(_ el: AXUIElement, _ name: String) -> Bool {
    var b: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(el, name as CFString, &b) == .success && b.boolValue
}
func axFrame(_ el: AXUIElement) -> [String: Double]? {
    guard let pos = axAttr(el, "AXPosition"), let size = axAttr(el, "AXSize") else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return ["x": p.x, "y": p.y, "w": s.width, "h": s.height]
}
func axRange(_ el: AXUIElement, _ name: String = "AXSelectedTextRange") -> CFRange? {
    guard let v = axAttr(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var r = CFRange(location: 0, length: 0)
    AXValueGetValue(v as! AXValue, .cfRange, &r)
    return r
}
func axBoundsForRange(_ el: AXUIElement, _ range: CFRange) -> [String: Double]? {
    var r = range
    guard let rv = AXValueCreate(.cfRange, &r) else { return nil }
    var out: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForRange" as CFString, rv, &out) == .success,
          let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(out as! AXValue, .cgRect, &rect)
    return ["x": rect.origin.x, "y": rect.origin.y, "w": rect.size.width, "h": rect.size.height]
}

/// Raw node: everything the normalizer needs, no frames except for debugging.
func walk(_ el: AXUIElement, depth: Int = 0) -> [String: Any] {
    var n: [String: Any] = [:]
    func put(_ k: String, _ v: Any?) { if let v { n[k] = v } }
    put("role", axString(el, "AXRole"))
    put("subrole", axString(el, "AXSubrole"))
    put("identifier", axString(el, "AXIdentifier"))
    put("title", axString(el, "AXTitle"))
    put("label", axString(el, "AXDescription"))
    put("placeholder", axString(el, "AXPlaceholderValue"))
    if let v = axAttr(el, "AXValue") { put("value", (v as? String) ?? (v as? NSNumber)?.stringValue) }
    n["valueSettable"] = axSettable(el, "AXValue")
    n["actions"] = axActions(el)
    put("frame", axFrame(el))
    if depth < 40, let kids = axAttr(el, "AXChildren") as? [AXUIElement], !kids.isEmpty {
        n["children"] = kids.map { walk($0, depth: depth + 1) }
    }
    return n
}

func flatten(_ el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    var out = [el]
    if depth < 40, let kids = axAttr(el, "AXChildren") as? [AXUIElement] {
        for k in kids { out += flatten(k, depth: depth + 1) }
    }
    return out
}

// MARK: launch the fixture (interactive mode: no --self-test; last argv slot is a flag, never a bare path)

// AppKit restores the last window frame from the fixture's defaults (domain = executable name). The self-test clears those keys
// itself; interactive launches must start from the declared default size too, or the first layout depends on the previous run.
func clearSavedWindowFrames() {
    let domain = URL(fileURLWithPath: fixtureBin).lastPathComponent
    let list = Process()
    list.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    list.arguments = ["read", domain]
    let pipe = Pipe()
    list.standardOutput = pipe
    list.standardError = FileHandle.nullDevice
    guard (try? list.run()) != nil else { return }
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    list.waitUntilExit()
    for line in text.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\"NSWindow Frame "), let end = t.dropFirst().firstIndex(of: "\"") else { continue }
        let key = String(t[t.index(after: t.startIndex)..<end])
        let del = Process()
        del.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        del.arguments = ["delete", domain, key]
        del.standardError = FileHandle.nullDevice
        try? del.run()
        del.waitUntilExit()
        eprint("cleared saved window frame: \(key)")
    }
}
clearSavedWindowFrames()

let proc = Process()
proc.executableURL = URL(fileURLWithPath: fixtureBin)
proc.arguments = ["--events", eventsPath] + launchArgs + ["--f1-cross-interactive"]
let stdinPipe = Pipe()
proc.standardInput = stdinPipe
let stdoutPath = eventsPath + ".stdout"
FileManager.default.createFile(atPath: stdoutPath, contents: nil)
let stdoutHandle = FileHandle(forWritingAtPath: stdoutPath)
proc.standardOutput = stdoutHandle
proc.standardError = stdoutHandle
try? FileManager.default.removeItem(atPath: eventsPath)
do { try proc.run() } catch { eprint("launch failed: \(error)"); exit(2) }
let pid = proc.processIdentifier
eprint("fixture pid=\(pid)")
let appEl = AXUIElementCreateApplication(pid)

func shutdownAndExit(_ code: Int32) -> Never {
    if proc.isRunning {
        try? stdinPipe.fileHandleForWriting.write(contentsOf: Data("{\"step\":\"quit\"}\n".utf8))
        for _ in 0..<30 where proc.isRunning { usleep(100_000) }
        if proc.isRunning { proc.terminate() }
    }
    exit(code)
}

func eventsContain(_ needle: String) -> Bool {
    guard let s = try? String(contentsOfFile: eventsPath, encoding: .utf8) else { return false }
    return s.contains(needle)
}
func waitFor(_ what: String, timeout: Double = 15, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        usleep(50_000)
    }
    eprint("TIMEOUT waiting for \(what)")
    return false
}

guard waitFor("root-appear", timeout: 20, { eventsContain("\"root-appear\"") }) else { shutdownAndExit(2) }
usleep(800_000)   // first layout/AX publication

// MARK: per-step observation

func elementById(_ id: String) -> AXUIElement? { flatten(appEl).first { axString($0, "AXIdentifier") == id } }

func windowElement() -> AXUIElement? {
    (axAttr(appEl, "AXWindows") as? [AXUIElement])?.first
}

func identifiers(_ n: [String: Any]) -> [String] {
    var out: [String] = []
    if let i = n["identifier"] as? String, !i.isEmpty { out.append(i) }
    for c in (n["children"] as? [[String: Any]] ?? []) { out += identifiers(c) }
    return out
}
func signature(_ n: [String: Any]) -> String {
    let kids = (n["children"] as? [[String: Any]] ?? []).map(signature).joined(separator: ",")
    return "\(n["role"] as? String ?? "")|\(n["identifier"] as? String ?? "")|\(n["value"] as? String ?? "")|\(n["label"] as? String ?? "")[\(kids)]"
}

func observe(id: String, logical: String, native: String, startNs: UInt64, ops: [[String: Any]]) -> [String: Any] {
    var step: [String: Any] = ["id": id, "logicalAction": logical, "nativeMapping": native, "monoStartNs": startNs, "ops": ops]
    step["monoEndNs"] = DispatchTime.now().uptimeNanoseconds
    var focus: [String: Any] = [:]
    if proc.isRunning, let f = axAttr(appEl, "AXFocusedUIElement"), CFGetTypeID(f) == AXUIElementGetTypeID() {
        let fe = f as! AXUIElement
        focus["role"] = axString(fe, "AXRole") ?? ""
        focus["identifier"] = axString(fe, "AXIdentifier") ?? ""
        if let r = axRange(fe) {
            focus["selection"] = ["location": r.location, "length": r.length]
            // Caret bounds: one-character range at the caret (zero-length returns zero width); at end use the last char.
            let len = (axString(fe, "AXValue") ?? "").utf16.count
            let probe = r.location < len ? CFRange(location: r.location, length: 1) : CFRange(location: max(len - 1, 0), length: len > 0 ? 1 : 0)
            if let b = axBoundsForRange(fe, probe) { focus["caretProbeBounds"] = b }
        }
    }
    step["focus"] = focus
    // Window subtree only; the app menu bar is application chrome (verified in ax-routes/out/ax-tree.json).
    if proc.isRunning, windowElement() != nil {
        // Settle by state, not by time alone: re-walk until two consecutive trees agree and no field identifier is
        // duplicated (SwiftUI can keep a moved row's stale cell in the AX tree for a moment). Bounded at 6 s; a tree that
        // never settles is recorded as it is, so a persistent duplicate stays visible.
        var last = ""
        var root: [String: Any] = [:]
        var samples = 0
        let deadline = Date().addingTimeInterval(6)
        repeat {
            guard let w = windowElement() else { break }
            root = walk(appEl)
            root["children"] = [walk(w)]
            let ids = identifiers(root)
            let sig = signature(root)
            let unique = Set(ids).count == ids.count
            samples += 1
            if sig == last && unique { break }
            last = sig
            usleep(250_000)
        } while Date() < deadline
        step["axSamples"] = samples
        step["tree"] = root
    } else {
        step["closed"] = true    // no window to observe (the step closed it)
    }
    return step
}

// MARK: ops (Mac native mappings of the logical stimuli)

/// One keyDown/keyUp pair carrying the whole string: a single text insertion (what an IME commit does), not one commit per unit.
func typeChunk(_ s: String) -> String {
    let src = CGEventSource(stateID: .privateState)
    var units = Array(s.utf16)
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
        e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        e.postToPid(pid)
        usleep(60_000)
    }
    return "postToPid(chunk)"
}

func typeText(_ s: String) -> String {
    let src = CGEventSource(stateID: .privateState)
    for u in s.utf16 {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
            var c = u
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.postToPid(pid)
            usleep(40_000)
        }
    }
    return "postToPid"
}

var allOK = true
func note(_ ok: Bool, _ op: String, _ detail: String) -> [String: Any] {
    if !ok { allOK = false }
    return ["op": op, "ok": ok, "detail": detail]
}
func valueOf(_ id: String) -> String? { elementById(id).flatMap { axString($0, "AXValue") } }

/// Runs one op; returns (result record, native mapping text).
func perform(_ o: [String: Any]) -> ([String: Any], String) {
    let op = o["op"] as? String ?? "?"
    let ms = Double((o["ms"] as? Int) ?? 15000) / 1000
    switch op {
    case "focus":
        let id = o["id"] as! String
        guard let f = elementById(id) else { return (note(false, "AXFocused", "\(id) not found"), "AXFocused=true on \(id)") }
        let rc = AXUIElementSetAttributeValue(f, "AXFocused" as CFString, kCFBooleanTrue)
        usleep(300_000)
        let len = (axString(f, "AXValue") ?? "").utf16.count
        var end = CFRange(location: len, length: 0)
        let rc2 = AXValueCreate(.cfRange, &end).map { AXUIElementSetAttributeValue(f, "AXSelectedTextRange" as CFString, $0) } ?? .failure
        usleep(100_000)
        return (note(rc == .success && rc2 == .success, "AXFocused", "err=\(rc.rawValue)/\(rc2.rawValue)"),
                "AXFocused=true on \(id); AXSelectedTextRange=end")
    case "type":
        let text = o["text"] as! String
        let route = typeText(text)
        var ok = true
        if let id = o["expectId"] as? String, let v = o["expectValue"] as? String {
            ok = waitFor("\(id) == \(v)", timeout: 5) { valueOf(id) == v }
        }
        return (note(ok, "type", route), "CGEvent.postToPid(fixture) keyDown/keyUp per UTF-16 unit '\(text)'")
    case "typeChunk":
        let text = o["text"] as! String
        let route = typeChunk(text)
        var ok = true
        if let id = o["expectId"] as? String, let v = o["expectValue"] as? String {
            ok = waitFor("\(id) == \(v)", timeout: 5) { valueOf(id) == v }
        }
        return (note(ok, "typeChunk", route), "CGEvent.postToPid(fixture) one keyDown/keyUp carrying '\(text)' (single commit)")
    case "stdin":
        let j = o["json"] as! [String: Any]
        let data = (try? JSONSerialization.data(withJSONObject: j, options: [.sortedKeys])) ?? Data()
        let line = String(decoding: data, as: UTF8.self) + "\n"
        try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        return (note(true, "stdin", line.trimmingCharacters(in: .whitespacesAndNewlines)),
                "fixture stdin driver: \(j["step"] as? String ?? "?")")
    case "press":
        var el: AXUIElement?
        var label = o["id"] as? String ?? ""
        if let id = o["id"] as? String { el = elementById(id) }
        else if let after = o["afterId"] as? String, let title = o["title"] as? String {
            let all = flatten(appEl)
            if let at = all.firstIndex(where: { axString($0, "AXIdentifier") == after }) {
                el = all[(at + 1)...].first { axString($0, "AXRole") == "AXButton" && (axString($0, "AXTitle") == title || axString($0, "AXDescription") == title) }
            }
            label = "first '\(title)' button after \(after)"
        }
        guard let el else { return (note(false, "AXPress", "\(label) not found"), "AXPress \(label)") }
        let rc = AXUIElementPerformAction(el, "AXPress" as CFString)
        return (note(rc == .success, "AXPress", "err=\(rc.rawValue)"), "AXPress \(label)")
    case "setValue":
        let id = o["id"] as! String, v = o["value"] as! String
        guard let el = elementById(id) else { return (note(false, "AXValue", "\(id) not found"), "AXValue=\(v) on \(id)") }
        let rc = AXUIElementSetAttributeValue(el, "AXValue" as CFString, v as CFString)
        usleep(300_000)
        var detail = "err=\(rc.rawValue)"
        var native = "AXValue set '\(v)' on \(id)"
        if o["confirm"] as? Bool == true {
            let rc2 = AXUIElementPerformAction(el, "AXConfirm" as CFString)
            detail += " confirm=\(rc2.rawValue)"
            native += "; AXConfirm"
            usleep(300_000)
        }
        return (note(rc == .success, "AXValue", detail), native)
    case "replaceText":
        // Accessibility text replacement: focus, select the whole value (AXSelectedTextRange), set AXSelectedText.
        let id = o["id"] as! String, v = o["value"] as! String
        guard let el = elementById(id) else { return (note(false, "AXSelectedText", "\(id) not found"), "AXSelectedText=\(v) on \(id)") }
        let f = AXUIElementSetAttributeValue(el, "AXFocused" as CFString, kCFBooleanTrue)
        usleep(200_000)
        var all = CFRange(location: 0, length: (axString(el, "AXValue") ?? "").utf16.count)
        let r1 = AXValueCreate(.cfRange, &all).map { AXUIElementSetAttributeValue(el, "AXSelectedTextRange" as CFString, $0) } ?? .failure
        usleep(100_000)
        let r2 = AXUIElementSetAttributeValue(el, "AXSelectedText" as CFString, v as CFString)
        usleep(300_000)
        return (note(r2 == .success, "AXSelectedText", "focus=\(f.rawValue) range=\(r1.rawValue) set=\(r2.rawValue)"),
                "AXFocused; AXSelectedTextRange=all; AXSelectedText='\(v)' on \(id)")
    case "probeRows":
        // Diagnostic: AXRows vs AXChildren of the outline, as (identifier of first field in the row).
        func fieldIds(_ el: AXUIElement) -> [String] { flatten(el).compactMap { axString($0, "AXIdentifier") }.filter { $0.hasSuffix("/field") }.map { String($0.suffix(9).prefix(3)) } }
        var lines: [String] = []
        for outline in flatten(appEl) where axString(outline, "AXRole") == "AXOutline" {
            let rows = (axAttr(outline, "AXRows") as? [AXUIElement]) ?? []
            let kids = (axAttr(outline, "AXChildren") as? [AXUIElement]) ?? []
            lines.append("rows=\(rows.map { fieldIds($0).joined() }) children=\(kids.map { fieldIds($0).joined() })")
        }
        return (note(true, "probeRows", lines.joined(separator: " | ")), "diagnostic")
    case "waitNode":
        let id = o["id"] as! String
        let absent = o["absent"] as? Bool ?? false
        let ok = waitFor("\(id) \(absent ? "absent" : "present")", timeout: ms) { (elementById(id) == nil) == absent }
        return (note(ok, "waitNode", id), "poll AX tree until \(id) \(absent ? "absent" : "present")")
    case "waitValue":
        let id = o["id"] as! String, v = o["value"] as! String
        let ok = waitFor("\(id) == \(v)", timeout: ms) { valueOf(id) == v }
        return (note(ok, "waitValue", id), "poll AXValue of \(id) until '\(v)'")
    case "waitEvent":
        let c = o["contains"] as! String
        let ok = waitFor("event \(c)", timeout: ms) { eventsContain(c) }
        return (note(ok, "waitEvent", c), "poll fixture events until \(c)")
    case "wait":
        usleep(UInt32((o["ms"] as? Int ?? 0) * 1000))
        return (note(true, "wait", "\(o["ms"] as? Int ?? 0) ms"), "wait \(o["ms"] as? Int ?? 0) ms")
    default:
        return (note(false, op, "unknown op"), op)
    }
}

NSRunningApplication(processIdentifier: pid)?.activate()
usleep(500_000)

var steps: [[String: Any]] = []
for spec in planSteps {
    let sid = spec["id"] as! String
    let t0 = DispatchTime.now().uptimeNanoseconds
    var results: [[String: Any]] = []
    var natives: [String] = []
    for o in (spec["ops"] as? [[String: Any]] ?? []) {
        let (r, n) = perform(o)
        results.append(r)
        if (o["op"] as? String) != "wait" && !n.hasPrefix("poll ") { natives.append(n) }
    }
    usleep(UInt32((spec["settleMs"] as? Int ?? 500) * 1000))
    let native = natives.isEmpty ? "AX tree walk from application root" : natives.joined(separator: "; ")
    steps.append(observe(id: sid, logical: spec["logicalAction"] as? String ?? sid, native: native, startNs: t0, ops: results))
}

// MARK: write

var info = ProcessInfo.processInfo.operatingSystemVersionString
if let b = try? String(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist", encoding: .utf8),
   let r = b.range(of: "<key>ProductBuildVersion</key>") {
    let tail = b[r.upperBound...]
    if let a = tail.range(of: "<string>"), let z = tail.range(of: "</string>") { info = String(tail[a.upperBound..<z.lowerBound]) }
}
let v = ProcessInfo.processInfo.operatingSystemVersion
let raw: [String: Any] = [
    "platform": ["os": "macos", "osBuild": "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (\(info))", "arch": "arm64", "toolchain": "Swift 6.4"],
    "pid": Int(pid), "steps": steps, "allOK": allOK,
]
let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) steps=\(steps.count) ok=\(allOK)")
shutdownAndExit(allOK ? 0 : 1)
