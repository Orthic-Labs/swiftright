// Pure synthetic controls over actual shared function. No Windows/native calls.
import Foundation
func require(_ pass: Bool) { if !pass { fatalError("geometry control failed") } }
require(factorySnappedExtentCanMatch(159.4, 160))
require(factorySnappedExtentCanMatch(159.4, 159))
require(!factorySnappedExtentCanMatch(159.4, 161))
require(!factorySnappedExtentCanMatch(159.4, 158))
require(!factorySnappedExtentCanMatch(159.4, 159.4))
require(!factorySnappedExtentCanMatch(.nan, 160))
require(!factorySnappedExtentCanMatch(.infinity, 160))
require(!factorySnappedExtentCanMatch(-1, 0))
for origin: Float in [0, 0.1, 0.4, 0.49, 0.5, 0.9, 10.4, -0.4, -0.5, -10.5] {
 for extent: Float in [0, 0.1, 0.4, 1, 1.4, 159.4, 159.7, 160] {
  let snapped = (origin + extent).rounded() - origin.rounded()
  require(factorySnappedExtentCanMatch(extent, snapped, origin: origin.rounded()))
 }
}
print("synthetic geometry controls passed; native capture count0")

require(factorySnappedExtentCanMatch(159, 160, origin: -1))
require(!factorySnappedExtentCanMatch(159, 160, origin: 0))
require(!factorySnappedExtentCanMatch(159, 160, origin: -200))

require(factorySnappedExtentCanMatch(159, 158, origin: 1, scale: 1.25))
require(!factorySnappedExtentCanMatch(159, 157, origin: 1, scale: 1.25))
for scale: Float in [1, 1.25, 1.5, 2.5, 3] {
 for origin: Double in [-10.5, -0.5, 0.500002, 0, 0.4, 1.5] {
  for physical: Float in [0.1, 1, 1.4, 159, 159.4, 159.7, 160] {
   let extent = Double(physical / scale) * Double(scale)
   let snapped = (origin + extent).rounded() - origin.rounded()
   require(factorySnappedExtentCanMatch(physical, Float(snapped), origin: Float(origin.rounded()), scale: scale))
  }
 }
}
print("synthetic Float32/CGFloat edge controls passed")
