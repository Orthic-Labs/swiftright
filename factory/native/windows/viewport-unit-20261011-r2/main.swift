import Foundation
// Synthetic unit fixture: no renderer, native window, or desktop API calls.
var failures = [String]()
func check(_ value: Bool, _ name: String) { if !value { failures.append(name) } }
do {
    let m = try factoryClientSize(width: 800, height: 600, dpi: 240)
    check(m.scale == 2.5 && m.logicalWidth == 320 && m.logicalHeight == 240, "physical pixels to logical proposal")
    let q = try factoryClientSize(width: 768, height: 384, dpi: 192)
    check(q.logicalWidth == 384 && q.logicalHeight == 192, "second DPI conversion")
    let invalid: [(Int32, Int32, UInt32)] = [(0,600,240),(-1,600,240),(800,0,240),(32769,600,240),(800,600,0),(800,600,769)]
    for tuple in invalid {
        do { _ = try factoryClientSize(width: tuple.0, height: tuple.1, dpi: tuple.2); failures.append("invalid metrics accepted") }
        catch { }
    }
} catch { failures.append(String(describing: error)) }
print("FACTORY_SYNTHETIC_VIEWPORT_UNIT failures=\(failures.count) nativeCaseCaptureCount=0")
failures.forEach { print($0) }
fflush(stdout)
exit(failures.isEmpty ? 0 : 1)
