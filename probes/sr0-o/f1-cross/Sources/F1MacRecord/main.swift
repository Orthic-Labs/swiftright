import AppKit
import ApplicationServices
import Foundation

// F1MacRecord: launches the F1 fixture (non-self-test mode), drives it with the F1 logical stimulus through AX and
// CGEvent.postToPid (never the global HID tap), and dumps raw per-step observations for F1Assemble.
//   F1MacRecord --fixture <FixtureApp binary> --events <jsonl path> --out <raw json> [--keep]
// Fixture stdin carries the fake-engine release (the fixture's driver protocol). Exit: 0 ok, 1 a step failed, 2 setup error.

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func argValue(_ n: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
    return a[i + 1]
}
guard let fixtureBin = argValue("--fixture"), let eventsPath = argValue("--events"), let outPath = argValue("--out") else {
    eprint("usage: F1MacRecord --fixture <FixtureApp> --events <jsonl> --out <raw.json>")
    exit(2)
}
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

let proc = Process()
proc.executableURL = URL(fileURLWithPath: fixtureBin)
proc.arguments = ["--events", eventsPath, "--fixture", "F1", "--f1-cross-interactive"]
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

let rowPrefix = "F0000001-0000-4000-8000-"
func rowField(_ slot: Int) -> String { "row/\(rowPrefix)\(String(format: "%012d", slot))/field" }
func fieldElement(_ id: String) -> AXUIElement? { flatten(appEl).first { axString($0, "AXIdentifier") == id } }

func windowElement() -> AXUIElement? {
    (axAttr(appEl, "AXWindows") as? [AXUIElement])?.first
}

func observe(id: String, logical: String, native: String, startNs: UInt64, ops: [[String: Any]]) -> [String: Any] {
    var step: [String: Any] = ["id": id, "logicalAction": logical, "nativeMapping": native, "monoStartNs": startNs, "ops": ops]
    step["monoEndNs"] = DispatchTime.now().uptimeNanoseconds
    var focus: [String: Any] = [:]
    if let f = axAttr(appEl, "AXFocusedUIElement"), CFGetTypeID(f) == AXUIElementGetTypeID() {
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
    if let w = windowElement() {
        var root = walk(appEl)
        root["children"] = [walk(w)]
        step["tree"] = root
    }
    return step
}

// MARK: stimulus (F1 logical script, Mac native mappings)

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

var steps: [[String: Any]] = []
var allOK = true
func note(_ ok: Bool, _ op: String, _ detail: String) -> [String: Any] {
    if !ok { allOK = false }
    return ["op": op, "ok": ok, "detail": detail]
}

NSRunningApplication(processIdentifier: pid)?.activate()
usleep(500_000)

// initial
let t0 = DispatchTime.now().uptimeNanoseconds
usleep(500_000)
steps.append(observe(id: "initial", logical: "launch-and-snapshot", native: "AX tree walk from application root", startNs: t0, ops: []))

// focus_row5
let t1 = DispatchTime.now().uptimeNanoseconds
var ops: [[String: Any]] = []
if let f = fieldElement(rowField(5)) {
    let rc = AXUIElementSetAttributeValue(f, "AXFocused" as CFString, kCFBooleanTrue)
    ops.append(note(rc == .success, "AXFocused", "err=\(rc.rawValue)"))
    usleep(300_000)
    let len = (axString(f, "AXValue") ?? "").utf16.count
    var end = CFRange(location: len, length: 0)
    let rc2 = AXValueCreate(.cfRange, &end).map { AXUIElementSetAttributeValue(f, "AXSelectedTextRange" as CFString, $0) } ?? .failure
    ops.append(note(rc2 == .success, "AXSelectedTextRange=end", "err=\(rc2.rawValue)"))
} else { ops.append(note(false, "AXFocused", "row 5 field not found")) }
usleep(400_000)
steps.append(observe(id: "focus_row5", logical: "focus row 5 field", native: "AXFocused=true on row/<uuid5>/field; AXSelectedTextRange=end", startNs: t1, ops: ops))

// type_abc
let t2 = DispatchTime.now().uptimeNanoseconds
let route = typeText("abc")
let okAbc = waitFor("row5 'Row 5abc'", timeout: 5) { fieldElement(rowField(5)).flatMap { axString($0, "AXValue") } == "Row 5abc" }
usleep(300_000)
steps.append(observe(id: "type_abc", logical: "type abc", native: "CGEvent.postToPid(fixture) keyDown/keyUp per UTF-16 unit 'abc'", startNs: t2,
                     ops: [note(okAbc, "type", route)]))

// engine_insert_above: fake-engine release through the fixture's stdin driver
let t3 = DispatchTime.now().uptimeNanoseconds
let line = "{\"step\":\"release\",\"key\":\"insert-above\",\"value\":0}\n"
try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(line.utf8))
let okIns = waitFor("inserted row 99 field", timeout: 15) { fieldElement(rowField(99)) != nil }
usleep(500_000)
steps.append(observe(id: "engine_insert_above", logical: "engine inserts row at index 0", native: "fixture stdin driver: release key insert-above (fake engine)", startNs: t3,
                     ops: [note(okIns, "release", "stdin")]))

// type_d
let t4 = DispatchTime.now().uptimeNanoseconds
_ = typeText("d")
let okD = waitFor("row5 'Row 5abcd'", timeout: 5) { fieldElement(rowField(5)).flatMap { axString($0, "AXValue") } == "Row 5abcd" }
usleep(500_000)
steps.append(observe(id: "type_d", logical: "type d", native: "CGEvent.postToPid(fixture) keyDown/keyUp per UTF-16 unit 'd'", startNs: t4, ops: [note(okD, "type", "postToPid")]))

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
