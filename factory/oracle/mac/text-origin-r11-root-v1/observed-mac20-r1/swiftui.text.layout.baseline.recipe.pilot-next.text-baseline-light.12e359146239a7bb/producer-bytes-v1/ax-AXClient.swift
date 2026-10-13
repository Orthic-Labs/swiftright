import ApplicationServices
import CryptoKit
import Darwin
import Foundation

func arg(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}
func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    print(String(decoding: data, as: UTF8.self))
}
func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func tree(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, attribute) in [("role", "AXRole"), ("subrole", "AXSubrole"), ("identifier", "AXIdentifier"), ("title", "AXTitle"), ("label", "AXDescription")] {
        if let string = attr(element, attribute) as? String { result[key] = string }
    }
    if let value = attr(element, "AXValue") {
        if let value = value as? String { result["value"] = value }
        else if let value = value as? NSNumber { result["value"] = value.stringValue }
    }
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success { result["actions"] = actions as? [String] ?? [] }
    if let position = attr(element, "AXPosition"), let size = attr(element, "AXSize"), CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        result["frame"] = ["x": p.x, "y": p.y, "w": s.width, "h": s.height]
    }
    if depth < 20, let children = attr(element, "AXChildren") as? [AXUIElement] { result["children"] = children.prefix(256).map { tree($0, depth: depth + 1) } }
    return result
}
let trusted = AXIsProcessTrusted()
if CommandLine.arguments.contains("--preflight") {
    emit(["axTrusted": trusted, "permissionRequests": false, "pid": ProcessInfo.processInfo.processIdentifier]); exit(0)
}
guard trusted else { emit(["status": "HELD", "reason": "no-prompt AX trust preflight denied", "permissionRequests": false]); exit(0) }
guard let pid = arg("--pid").flatMap(Int32.init), let expectedPath = arg("--owner-path"), let expectedHash = arg("--owner-hash"), let title = arg("--window-title"), expectedPath.hasPrefix("/Users/adrdsouza/Library/Caches/SwiftRightFactory/") else { exit(64) }
var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { emit(["status": "HELD", "reason": "target owner PID path unavailable"]); exit(0) }
let actualPath = String(cString: buffer)
guard actualPath == expectedPath, let binary = try? Data(contentsOf: URL(fileURLWithPath: actualPath)) else { emit(["status": "HELD", "reason": "target owner path differs"]); exit(0) }
let hash = "sha256:" + SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
guard hash == expectedHash else { emit(["status": "HELD", "reason": "target owner binary hash differs"]); exit(0) }
let application = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(application, 1)
let deadline = Date().addingTimeInterval(5)
var selected: AXUIElement?
repeat {
    if let windows = attr(application, "AXWindows") as? [AXUIElement] { selected = windows.first { attr($0, "AXTitle") as? String == title } }
    if selected != nil { break }
    usleep(50_000)
} while Date() < deadline
guard let selected else { emit(["status": "HELD", "reason": "owned target window title unavailable", "pid": pid, "ownerPath": actualPath, "ownerHash": hash]); exit(0) }
let raw = tree(selected)
emit(["status": "OBSERVED", "mode": "fresh-external-ax", "permissionRequests": false, "pid": pid, "clientPID": ProcessInfo.processInfo.processIdentifier, "ownerPath": actualPath, "ownerHash": hash, "windowTitle": title, "steps": [["id": "snapshot", "tree": raw]]])
