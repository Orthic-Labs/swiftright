import ApplicationServices
import CryptoKit
import Darwin
import Foundation

private let expectedCase = "swiftui.disabled.recipe/case/f113195a59446fc4"
private let expectedCaseHash = "sha256:d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99"
private let expectedSourceHash = "sha256:68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
private let expectedOwnerPath = "/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/swiftui.disabled.recipe_case_f113195a59446fc4/capture-host"
private let expectedOwnerHash = "sha256:d555759e14425b5c38751935ed54bc18836bbbd8703362f85e33661e99d0c7d6"

private func arg(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

private func digest(_ data: Data) -> String {
    "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    print(String(decoding: data, as: UTF8.self))
}

private func copyAttribute(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (status, value)
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    let (status, value) = copyAttribute(element, name)
    return status == .success ? value as? String : nil
}

private func enabledAttribute(_ element: AXUIElement) -> [String: Any] {
    let (status, value) = copyAttribute(element, "AXEnabled")
    var result: [String: Any] = ["attribute": "AXEnabled", "axError": Int(status.rawValue)]
    guard status == .success, let value else {
        result["status"] = "unavailable"
        return result
    }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        result["status"] = "observed-bool"
        result["value"] = CFBooleanGetValue((value as! CFBoolean))
        return result
    }
    if let number = value as? NSNumber, CFGetTypeID(value) == CFNumberGetTypeID() {
        result["status"] = "observed-number"
        result["value"] = number.boolValue
        result["rawNumber"] = number.stringValue
        return result
    }
    result["status"] = "observed-nonboolean"
    result["cfTypeID"] = CFGetTypeID(value)
    result["description"] = String(describing: value)
    return result
}

private func node(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, attrName) in [("role", "AXRole"), ("subrole", "AXSubrole"), ("identifier", "AXIdentifier"), ("title", "AXTitle"), ("label", "AXDescription")] {
        if let value = stringAttribute(element, attrName) { result[key] = value }
    }
    if result["role"] as? String == "AXButton" { result["enabledAttribute"] = enabledAttribute(element) }
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success { result["actions"] = actions as? [String] ?? [] }
    if let position = copyAttribute(element, "AXPosition").1, let size = copyAttribute(element, "AXSize").1,
       CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
        var point = CGPoint.zero, dimensions = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        result["frame"] = ["x": point.x, "y": point.y, "w": dimensions.width, "h": dimensions.height]
    }
    if depth < 20, let children = copyAttribute(element, "AXChildren").1 as? [AXUIElement] {
        result["children"] = children.prefix(256).map { node($0, depth: depth + 1) }
    }
    return result
}

let trusted = AXIsProcessTrusted()
if CommandLine.arguments.contains("--preflight") {
    emit(["kind": "no-prompt-ax-preflight", "axTrusted": trusted, "permissionRequests": false,
          "pid": ProcessInfo.processInfo.processIdentifier, "caseId": expectedCase,
          "caseHash": expectedCaseHash, "sourceHash": expectedSourceHash])
    exit(0)
}
guard trusted else {
    emit(["status": "HELD", "reason": "AXIsProcessTrusted false; no permission request attempted", "permissionRequests": false,
          "pid": ProcessInfo.processInfo.processIdentifier, "caseId": expectedCase, "sourceHash": expectedSourceHash])
    exit(0)
}
guard arg("--case-id") == expectedCase, arg("--case-hash") == expectedCaseHash,
      arg("--source-hash") == expectedSourceHash,
      let pid = arg("--pid").flatMap(Int32.init), arg("--owner-path") == expectedOwnerPath,
      arg("--owner-hash") == expectedOwnerHash,
      let startedAt = arg("--owner-started-at"), let title = arg("--window-title"),
      title == "SwiftRightFactory-" + expectedCase else {
    emit(["status": "HELD", "reason": "case/source/owner invocation pins mismatch", "permissionRequests": false])
    exit(64)
}
var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
    emit(["status": "HELD", "reason": "target process path unavailable", "permissionRequests": false, "pid": pid])
    exit(0)
}
let actualPath = String(cString: pathBuffer)
guard actualPath == expectedOwnerPath, let binary = try? Data(contentsOf: URL(fileURLWithPath: actualPath)),
      digest(binary) == expectedOwnerHash else {
    emit(["status": "HELD", "reason": "target process path or binary hash mismatch", "permissionRequests": false,
          "pid": pid, "ownerPath": actualPath])
    exit(0)
}
let application = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(application, 1)
let deadline = Date().addingTimeInterval(5)
var selected: AXUIElement?
repeat {
    if let windows = copyAttribute(application, "AXWindows").1 as? [AXUIElement] {
        selected = windows.first { stringAttribute($0, "AXTitle") == title }
    }
    if selected != nil { break }
    usleep(50_000)
} while Date() < deadline
guard let selected else {
    emit(["status": "HELD", "reason": "owned window unavailable", "permissionRequests": false,
          "pid": pid, "ownerPath": actualPath, "ownerHash": expectedOwnerHash, "windowTitle": title])
    exit(0)
}
let rawTree = node(selected)
emit(["kind": "fresh-external-ax-enabled-observation", "status": "OBSERVED", "permissionRequests": false,
      "clientPID": ProcessInfo.processInfo.processIdentifier, "pid": pid, "ownerPID": pid,
      "ownerPath": actualPath, "ownerBinarySha256": expectedOwnerHash,
      "ownerStartedAt": startedAt, "windowTitle": title, "caseId": expectedCase,
      "caseSha256": expectedCaseHash, "sourceSha256": expectedSourceHash,
      "steps": [["id": "snapshot", "tree": rawTree]]])
