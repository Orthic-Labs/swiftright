import ApplicationServices
import Foundation

struct AXResult: Encodable {
    let status: String
    let detail: String
    let values: [String: String]
}

func finish(_ result: AXResult, _ code: Int32) -> Never {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: (try? encoder.encode(result)) ?? Data(), as: UTF8.self))
    Foundation.exit(code)
}

func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func button(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 12 else { return nil }
    if stringValue(element, kAXRoleAttribute as CFString) == kAXButtonRole as String,
       stringValue(element, kAXTitleAttribute as CFString) == "Probe control" { return element }
    for child in children(element) {
        if let found = button(in: child, depth: depth + 1) { return found }
    }
    return nil
}

let arguments = CommandLine.arguments
guard let index = arguments.firstIndex(of: "--pid"), index + 1 < arguments.endIndex,
      let targetPID = pid_t(arguments[index + 1]) else {
    finish(AXResult(status: "BLOCKED", detail: "Usage: mac-capture-ax-client --pid <pid>.", values: [:]), 64)
}

let app = AXUIElementCreateApplication(targetPID)
var value: CFTypeRef?
let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
guard result == .success, let windows = value as? [AXUIElement], !windows.isEmpty else {
    finish(AXResult(status: "BLOCKED", detail: "External AX client could not read target windows; provision Accessibility only in VM if policy permits.", values: ["axError": String(result.rawValue)]), 2)
}
for window in windows {
    if let found = button(in: window), let role = stringValue(found, kAXRoleAttribute as CFString) {
        finish(AXResult(status: "OBSERVED", detail: "Separate AX client found target control.", values: ["role": role, "title": stringValue(found, kAXTitleAttribute as CFString) ?? ""]), 0)
    }
}
finish(AXResult(status: "UNOBSERVED", detail: "Separate AX client read target windows but found no AXButton.", values: ["windows": String(windows.count)]), 3)
