import Foundation

// Pure serializer seam shared by native logger & headless controls.
// CGFloat never crosses JSON boundary; integer identity fields remain exact.
struct PaddingMetricsSnapshotValues {
    let bridgeWidth: UInt32, bridgeHeight: UInt32
    let bridgeScale: Float
    let active: Bool
    let clientWidth: UInt32, clientHeight: UInt32, dpi: UInt32
    let clientScale: Float
    let logicalWidth: Double, logicalHeight: Double
    let pid: UInt32, thread: UInt32
    let hwnd: UInt
}
func factoryPaddingMetricsSnapshotPayload(_ value: PaddingMetricsSnapshotValues,
    phase: String, source: String, extra: [String: Any] = [:]) -> [String: Any] {
    var payload = extra
    payload["record"] = "metrics-snapshot"
    payload["phase"] = phase
    payload["source"] = source
    let bridge: [String: Any] = ["widthPx": value.bridgeWidth, "heightPx": value.bridgeHeight,
        "scale": Double(value.bridgeScale), "active": value.active]
    let client: [String: Any] = ["widthPx": value.clientWidth, "heightPx": value.clientHeight,
        "dpi": value.dpi, "scale": Double(value.clientScale),
        "logicalWidth": value.logicalWidth, "logicalHeight": value.logicalHeight]
    payload["bridge"] = bridge
    payload["ownedClient"] = client
    payload["pid"] = value.pid
    payload["thread"] = value.thread
    payload["hwnd"] = value.hwnd
    return payload
}
func factoryPaddingMetricsJSONText(_ payload: [String: Any], monotonicNS: UInt64,
    utc: String) throws -> String {
    var value = payload
    value["monotonicNS"] = monotonicNS
    value["utc"] = utc
    guard JSONSerialization.isValidJSONObject(value) else {
        throw NSError(domain: "FactoryMetricsLogSerialization", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid JSON payload before encoding"])
    }
    let data: Data
    do { data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    catch { throw NSError(domain: "FactoryMetricsLogSerialization", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "JSON encoding failed", NSUnderlyingErrorKey: error]) }
    guard let text = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "FactoryMetricsLogSerialization", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "JSON UTF8 conversion failed"])
    }
    return text
}
