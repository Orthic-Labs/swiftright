import AppKit
import ApplicationServices
import Foundation

// Out-of-process AX recorder for the SR0 F1-lite probe. Does not prompt; does not touch TCC.

func absPath(_ p: String) -> String {
    URL(fileURLWithPath: p).standardizedFileURL.path
}

let selfBinary = absPath(Bundle.main.executablePath ?? CommandLine.arguments[0])
let trusted = AXIsProcessTrusted()
print("AXIsProcessTrusted=\(trusted)")
if !trusted {
    print("BLOCKER: Accessibility permission missing for binary: \(selfBinary)")
    print("Probe did not prompt and did not modify TCC. Grant it manually, then rerun.")
    exit(2)
}

// MARK: helpers

func axAttr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
    return (v as AnyObject)
}

func axValueJSON(_ v: AXValue) -> Any {
    let t = AXValueGetType(v)
    switch t {
    case .cgPoint:
        var p = CGPoint.zero
        AXValueGetValue(v, .cgPoint, &p)
        return ["x": p.x, "y": p.y]
    case .cgSize:
        var s = CGSize.zero
        AXValueGetValue(v, .cgSize, &s)
        return ["w": s.width, "h": s.height]
    case .cgRect:
        var r = CGRect.zero
        AXValueGetValue(v, .cgRect, &r)
        return ["x": r.origin.x, "y": r.origin.y, "w": r.size.width, "h": r.size.height]
    case .cfRange:
        var r = CFRange(location: 0, length: 0)
        AXValueGetValue(v, .cfRange, &r)
        return ["location": r.location, "length": r.length]
    default:
        return "AXValue(type=\(t.rawValue))"
    }
}

func jsonValue(_ o: AnyObject?) -> Any {
    guard let o else { return NSNull() }
    if let s = o as? String { return s }
    if let n = o as? NSNumber { return n }
    if CFGetTypeID(o) == AXValueGetTypeID() { return axValueJSON(o as! AXValue) }
    return String(describing: o)
}

func actionNames(_ el: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(el, &names) == .success, let names else { return [] }
    return (names as? [String]) ?? []
}

func frame(_ el: AXUIElement) -> Any {
    guard let pos = axAttr(el, "AXPosition"), let size = axAttr(el, "AXSize") else { return NSNull() }
    var p = CGPoint.zero
    var s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return ["x": p.x, "y": p.y, "w": s.width, "h": s.height]
}

func walk(_ el: AXUIElement, depth: Int) -> [String: Any] {
    var n: [String: Any] = [:]
    n["role"] = jsonValue(axAttr(el, "AXRole"))
    n["subrole"] = jsonValue(axAttr(el, "AXSubrole"))
    n["identifier"] = jsonValue(axAttr(el, "AXIdentifier"))
    n["title"] = jsonValue(axAttr(el, "AXTitle"))
    n["label"] = jsonValue(axAttr(el, "AXDescription"))
    n["value"] = jsonValue(axAttr(el, "AXValue"))
    n["actions"] = actionNames(el)
    n["frame"] = frame(el)
    if depth < 60, let kids = axAttr(el, "AXChildren") as? [AXUIElement], !kids.isEmpty {
        n["children"] = kids.map { walk($0, depth: depth + 1) }
    }
    return n
}

// Flatten in tree order (DFS) for identifier lookup.
func flatten(_ el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    var out = [el]
    if depth < 60, let kids = axAttr(el, "AXChildren") as? [AXUIElement] {
        for k in kids { out += flatten(k, depth: depth + 1) }
    }
    return out
}

func identifier(_ el: AXUIElement) -> String? {
    axAttr(el, "AXIdentifier") as? String
}

func stringValue(_ el: AXUIElement) -> String? {
    axAttr(el, "AXValue") as? String
}

func selectedRange(_ el: AXUIElement) -> CFRange? {
    guard let v = axAttr(el, "AXSelectedTextRange"), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var r = CFRange(location: 0, length: 0)
    AXValueGetValue(v as! AXValue, .cfRange, &r)
    return r
}

func boundsForRange(_ el: AXUIElement, _ range: CFRange) -> Any {
    var r = range
    guard let rv = AXValueCreate(.cfRange, &r) else { return "AXValueCreate failed" }
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForRange" as CFString, rv, &out)
    guard err == .success, let out, CFGetTypeID(out) == AXValueGetTypeID() else {
        return "err=\(err.rawValue)"
    }
    return axValueJSON(out as! AXValue)
}

func setAttr(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
    AXUIElementSetAttributeValue(el, name as CFString, value)
}

// Route: "hid" posts to the system HID tap (only when FixtureApp is frontmost, so keystrokes cannot reach another app);
// "pid" posts directly to the fixture process via postToPid.
@discardableResult
func typeText(_ s: String, pid: pid_t, route: String) -> String {
    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    let effective = route == "hid" && frontPID != pid ? "skipped_not_frontmost(front=\(frontPID))" : route
    if effective.hasPrefix("skipped") { return effective }
    let src = CGEventSource(stateID: .hidSystemState)
    for u in s.utf16 {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
            var c = u
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            if route == "hid" { e.post(tap: .cghidEventTap) } else { e.postToPid(pid) }
            usleep(40_000)
        }
    }
    return effective
}

// MARK: locate FixtureApp

let pid: pid_t
if let arg = CommandLine.arguments.dropFirst().first, let n = Int32(arg) {
    pid = n
} else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.executableURL?.lastPathComponent == "FixtureApp" }) {
    pid = app.processIdentifier
} else {
    print("FixtureApp not running")
    exit(3)
}
print("fixture pid=\(pid)")
let appEl = AXUIElementCreateApplication(pid)

// MARK: tree walk (canonical JSON)

let tree = walk(appEl, depth: 0)
let treeData = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
let treeURL = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/out/ax-tree.json")
try? FileManager.default.createDirectory(at: treeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try treeData.write(to: treeURL)
print("TREE_JSON_BEGIN")
print(String(decoding: treeData, as: UTF8.self))
print("TREE_JSON_END")

let all = flatten(appEl)
let rowFields = all.filter { (identifier($0) ?? "").hasPrefix("row/") && (identifier($0) ?? "").hasSuffix("/field") }
let insertButtons = all.filter { identifier($0) == "toolbar/insert" }
let rowFieldCount = rowFields.count
let hasInsertID = !insertButtons.isEmpty
print("row field identifiers found=\(rowFieldCount) toolbar/insert found=\(hasInsertID)")

// MARK: F1-lite

guard rowFields.count >= 5 else { print("FAIL: fewer than 5 row fields"); exit(4) }
let row5 = rowFields[4]
let row5ID = identifier(row5)!
print("row5 identifier=\(row5ID)")

@MainActor func focusedInfo() -> [String: Any] {
    var info: [String: Any] = [:]
    if let f = axAttr(appEl, "AXFocusedUIElement"), CFGetTypeID(f) == AXUIElementGetTypeID() {
        let fe = f as! AXUIElement
        info["focusedRole"] = jsonValue(axAttr(fe, "AXRole"))
        info["focusedIdentifier"] = jsonValue(axAttr(fe, "AXIdentifier"))
        info["focusedValue"] = jsonValue(axAttr(fe, "AXValue"))
        if let r = selectedRange(fe) {
            info["selectedRange"] = ["location": r.location, "length": r.length]
            info["boundsForSelectedRange"] = boundsForRange(fe, r)
        } else {
            info["selectedRange"] = "unreadable"
        }
    } else {
        info["focusedIdentifier"] = NSNull()
    }
    return info
}

// Re-locate row 5 by its stable identifier after each step.
@MainActor func row5Now() -> AXUIElement? {
    flatten(appEl).first { identifier($0) == row5ID }
}

var steps: [[String: Any]] = []
@MainActor func snap(_ label: String, extra: [String: Any] = [:]) {
    var s = focusedInfo()
    s["step"] = label
    if let r5 = row5Now() {
        s["row5Value"] = jsonValue(axAttr(r5, "AXValue"))
        s["row5Found"] = true
    } else {
        s["row5Found"] = false
    }
    s["rowFieldCount"] = flatten(appEl).filter { (identifier($0) ?? "").hasPrefix("row/") }.count
    s["focusIsRow5"] = (s["focusedIdentifier"] as? String) == row5ID
    for (k, v) in extra { s[k] = v }
    steps.append(s)
    let data = try! JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])
    print("STEP \(String(decoding: data, as: UTF8.self))")
}

// Bring fixture to front; "hid" typing is only used when it is actually frontmost.
NSRunningApplication(processIdentifier: pid)?.activate()
usleep(500_000)

let focusRC = setAttr(row5, "AXFocused", kCFBooleanTrue)
print("set AXFocused on row5 err=\(focusRC.rawValue)")
usleep(300_000)
// Put caret at end of row 5 text.
let len = (stringValue(row5) ?? "").utf16.count
var endRange = CFRange(location: len, length: 0)
let caretRC = AXValueCreate(.cfRange, &endRange).map { setAttr(row5, "AXSelectedTextRange", $0) } ?? .failure
print("set AXSelectedTextRange to end err=\(caretRC.rawValue)")
usleep(200_000)
snap("after_focus", extra: ["setFocusErr": Int(focusRC.rawValue), "setCaretErr": Int(caretRC.rawValue)])

let valueBeforeType = stringValue(row5) ?? ""
let routeAbc = typeText("abc", pid: pid, route: "hid")
let routeAbcUsed = routeAbc.hasPrefix("skipped") ? typeText("abc", pid: pid, route: "pid") : routeAbc
print("typing abc route=\(routeAbc) used=\(routeAbcUsed)")
usleep(400_000)
snap("after_type_abc", extra: ["valueBefore": valueBeforeType])

var pressRC: AXError = .failure
if let btn = insertButtons.first {
    pressRC = AXUIElementPerformAction(btn, "AXPress" as CFString)
}
print("AXPress toolbar/insert err=\(pressRC.rawValue)")
usleep(800_000)
snap("after_axpress_insert", extra: ["axPressErr": Int(pressRC.rawValue)])

let routeD = typeText("d", pid: pid, route: routeAbcUsed == "hid" ? "hid" : "pid")
print("typing d route=\(routeD)")
usleep(400_000)
snap("after_type_d")

// MARK: summary routes

let rowsAfter = flatten(appEl).filter { (identifier($0) ?? "").hasPrefix("row/") }.count
let afterPress = steps.first { ($0["step"] as? String) == "after_axpress_insert" } ?? [:]
let afterAbc = steps.first { ($0["step"] as? String) == "after_type_abc" } ?? [:]
let afterD = steps.first { ($0["step"] as? String) == "after_type_d" } ?? [:]
let afterFocus = steps.first { ($0["step"] as? String) == "after_focus" } ?? [:]

func yn(_ b: Bool) -> String { b ? "WORKS" : "FAILS" }
let r1 = !all.isEmpty
let r2 = rowFieldCount >= 10 && hasInsertID
let r3 = pressRC == .success && rowsAfter == 11
let r4 = (afterFocus["focusIsRow5"] as? Bool) == true && focusRC == .success
let r5 = afterFocus["selectedRange"] is [String: Any]
let r6 = !(afterFocus["boundsForSelectedRange"] is String) && afterFocus["boundsForSelectedRange"] != nil
let r7 = ((afterAbc["row5Value"] as? String) ?? "").hasSuffix("abc")
let r8 = (afterPress["focusIsRow5"] as? Bool) == true && ((afterPress["row5Value"] as? String) ?? "").hasSuffix("abc")
let r9 = ((afterD["row5Value"] as? String) ?? "").hasSuffix("abcd")

print("SUMMARY")
print("tree walk: \(yn(r1)) nodes-from-root-flatten=\(all.count)")
print("identifiers present: \(yn(r2)) row fields=\(rowFieldCount) toolbar/insert=\(hasInsertID)")
print("AXPress toolbar/insert: \(yn(r3)) err=\(pressRC.rawValue) rows after=\(rowsAfter)")
print("focus set (AXFocused on row5): \(yn(r4)) focusedIsRow5=\(afterFocus["focusIsRow5"] ?? "nil")")
print("AXSelectedTextRange readable: \(yn(r5)) \(afterFocus["selectedRange"] ?? "nil")")
print("AXBoundsForRange readable: \(yn(r6)) \(afterFocus["boundsForSelectedRange"] ?? "nil")")
print("CGEvent typing reaches field: \(yn(r7)) row5Value after abc=\(afterAbc["row5Value"] ?? "nil")")
print("row5 identity keeps focus after insert: \(yn(r8)) focusIsRow5=\(afterPress["focusIsRow5"] ?? "nil") value=\(afterPress["row5Value"] ?? "nil")")
print("typing 'd' after insert lands on row5: \(yn(r9)) value=\(afterD["row5Value"] ?? "nil") focusIsRow5=\(afterD["focusIsRow5"] ?? "nil")")

let stepsData = try JSONSerialization.data(withJSONObject: steps, options: [.prettyPrinted, .sortedKeys])
try stepsData.write(to: URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/out/f1-lite-steps.json"))
