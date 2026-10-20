import Foundation
import SwiftRightRuntime
// Times PathRasterizer on the notch ring (inset circle, trim 0..0.62, round cap, rotated -90, 60 pt at scale 2.5): one animated frame = one raster.
let rect = CGRect(x: 0, y: 0, width: 60, height: 60)
var p = Path(); p.addEllipse(in: rect.insetBy(dx: 3, dy: 3))
let trimmed = p.trimmedPath(from: 0, to: 0.62)
let rot = CGAffineTransform(translationX: 75, y: 75).rotated(by: -.pi / 2).translatedBy(x: -75, y: -75)
let style = StrokeStyle(lineWidth: 6, lineCap: .round)
var times: [Double] = []
for i in 0..<200 {
    let spin = CGAffineTransform(translationX: 75, y: 75).rotated(by: Double(i) * 0.03).translatedBy(x: -75, y: -75)
    let t0 = DispatchTime.now().uptimeNanoseconds
    _ = try PathRasterizer.rasterize(path: trimmed, transform: rot.concatenating(spin), scale: 2.5, strokeRGBA: 0x3399FFFF, strokeStyle: style)
    times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
}
times.sort()
print(String(format: "ring raster ms: p50 %.3f p95 %.3f max %.3f (n=%d)", times[100], times[190], times.last!, times.count))
