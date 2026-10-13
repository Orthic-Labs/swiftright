import Foundation
import SwiftUI

private let outputCap = 60 * 1024
private let recordCap = 16

private struct Sample {
    let id: String
    let rect: CGRect
    let radius: CGFloat
}

private struct ElementRecord: Encodable {
    let kind: String
    let values: [Double]
}

private struct PathRecord: Encodable {
    let source: String
    let sample: String
    let style: String
    let bounds: [Double]
    let cornerRadius: Double
    let elements: [ElementRecord]
}

private func point(_ value: CGPoint) -> [Double] {
    [Double(value.x), Double(value.y)]
}

private func jsonLine(_ record: PathRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(record)
    data.append(0x0a)
    guard data.count < outputCap else {
        throw NSError(domain: "ContinuousGeometryProbe", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "record exceeds 60 KiB cap"])
    }
    return data
}

@main
private struct ContinuousGeometryProbe {
    static func main() throws {
        // Includes original witness geometry plus aspect/radius controls; no window or renderer.
        let samples = [
            Sample(id: "original-40x20-r6", rect: CGRect(x: 0, y: 0, width: 40, height: 20), radius: 6),
            Sample(id: "observed-105x55-r17_5", rect: CGRect(x: 0, y: 0, width: 105, height: 55), radius: 17.5),
            Sample(id: "square-64x64-r12", rect: CGRect(x: 0, y: 0, width: 64, height: 64), radius: 12),
            Sample(id: "wide-120x40-r10", rect: CGRect(x: 0, y: 0, width: 120, height: 40), radius: 10),
            Sample(id: "zero-radius-40x20", rect: CGRect(x: 0, y: 0, width: 40, height: 20), radius: 0),
            Sample(id: "clamped-radius-40x20", rect: CGRect(x: 0, y: 0, width: 40, height: 20), radius: 100),
            Sample(id: "translated-64x32-r8", rect: CGRect(x: 13, y: 7, width: 64, height: 32), radius: 8),
            Sample(id: "square-close-48x48-r23", rect: CGRect(x: 0, y: 0, width: 48, height: 48), radius: 23)
        ]
        let styles: [(String, RoundedCornerStyle)] = [
            ("continuous", .continuous), ("circular", .circular)
        ]
        var totalBytes = 0
        var records = 0
        for sample in samples {
            for (styleName, style) in styles {
                guard records < recordCap else {
                    throw NSError(domain: "ContinuousGeometryProbe", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "record cap exceeded"])
                }
                let path = RoundedRectangle(cornerRadius: sample.radius, style: style).path(in: sample.rect)
                var elements: [ElementRecord] = []
                path.forEach { element in
                    switch element {
                    case .move(let to):
                        elements.append(ElementRecord(kind: "move", values: point(to)))
                    case .line(let to):
                        elements.append(ElementRecord(kind: "line", values: point(to)))
                    case .quadCurve(let to, let control):
                        elements.append(ElementRecord(kind: "quad", values: point(to) + point(control)))
                    case .curve(let to, let control1, let control2):
                        elements.append(ElementRecord(kind: "cubic", values: point(to) + point(control1) + point(control2)))
                    case .closeSubpath:
                        elements.append(ElementRecord(kind: "close", values: []))
                    @unknown default:
                        elements.append(ElementRecord(kind: "unknown", values: []))
                    }
                }
                let record = PathRecord(source: "SwiftUI.RoundedRectangle.path(in:)", sample: sample.id,
                                        style: styleName,
                                        bounds: [Double(sample.rect.minX), Double(sample.rect.minY),
                                                 Double(sample.rect.width), Double(sample.rect.height)],
                                        cornerRadius: Double(sample.radius), elements: elements)
                let data = try jsonLine(record)
                totalBytes += data.count
                guard totalBytes < outputCap else {
                    throw NSError(domain: "ContinuousGeometryProbe", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "total output exceeds 60 KiB cap"])
                }
                FileHandle.standardOutput.write(data)
                records += 1
            }
        }
    }
}
