import Foundation
import WinSDK

struct FactoryClientSize {
    let width: UInt32
    let height: UInt32
    let dpi: UInt32
    var scale: Float { Float(dpi) / 96 }
    var logicalWidth: CGFloat { CGFloat(width) * 96 / CGFloat(dpi) }
    var logicalHeight: CGFloat { CGFloat(height) * 96 / CGFloat(dpi) }
}
func factoryClientSize(width: Int32, height: Int32, dpi: UInt32) throws -> FactoryClientSize {
    guard width > 0, height > 0, width <= 32768, height <= 32768,
          dpi >= 48, dpi <= 768 else {
        throw NSError(domain: "FactoryInvalidClientMetrics", code: 1)
    }
    return FactoryClientSize(width: UInt32(width), height: UInt32(height), dpi: dpi)
}
private struct FactoryWindowLookup {
    var hwnd: HWND?
    var matches: UInt32 = 0
    let pid: DWORD
    let thread: DWORD
}
private let factoryWindowEnumerator: WNDENUMPROC = { hwnd, context in
    guard let hwnd, let pointer = UnsafeMutablePointer<FactoryWindowLookup>(bitPattern: Int(context)) else { return 0 }
    var pid: DWORD = 0
    let thread = GetWindowThreadProcessId(hwnd, &pid)
    guard pid == pointer.pointee.pid, thread == pointer.pointee.thread else { return 1 }
    var buffer = [WCHAR](repeating: 0, count: 512)
    let count = buffer.withUnsafeMutableBufferPointer { GetWindowTextW(hwnd, $0.baseAddress, Int32($0.count)) }
    guard count > 0, String(decoding: buffer.prefix(Int(count)), as: UTF16.self) == "Alchemist FactoryProbe" else { return 1 }
    pointer.pointee.hwnd = hwnd
    pointer.pointee.matches += 1
    return 1
}
func factoryAbortOwnedForeground() throws {
    guard let foreground = GetForegroundWindow() else { return }
    var pid: DWORD = 0
    _ = GetWindowThreadProcessId(foreground, &pid)
    if pid == GetCurrentProcessId() { throw NSError(domain: "FactoryOwnedForegroundViolation", code: 1) }
}
struct FactoryOwnedClient {
    let hwnd: HWND
    let pid: DWORD
    let thread: DWORD
    let size: FactoryClientSize
}
func factoryOwnedClient(expected: HWND? = nil) throws -> FactoryOwnedClient {
    try factoryAbortOwnedForeground()
    let pid = GetCurrentProcessId(), thread = GetCurrentThreadId()
    var lookup = FactoryWindowLookup(pid: pid, thread: thread)
    let rc = withUnsafeMutablePointer(to: &lookup) {
        EnumThreadWindows(thread, factoryWindowEnumerator, LPARAM(Int(bitPattern: $0)))
    }
    guard rc != 0, lookup.matches == 1, let hwnd = lookup.hwnd,
          expected == nil || expected == hwnd, IsWindow(hwnd) != 0 else {
        throw NSError(domain: "FactoryOwnedRendererHWNDAmbiguous", code: 1)
    }
    var rectangle = RECT()
    guard GetClientRect(hwnd, &rectangle) != 0 else { throw NSError(domain: "FactoryClientRectUnavailable", code: 1) }
    let size = try factoryClientSize(width: rectangle.right - rectangle.left,
                                    height: rectangle.bottom - rectangle.top, dpi: GetDpiForWindow(hwnd))
    try factoryAbortOwnedForeground()
    return FactoryOwnedClient(hwnd: hwnd, pid: pid, thread: thread, size: size)
}
