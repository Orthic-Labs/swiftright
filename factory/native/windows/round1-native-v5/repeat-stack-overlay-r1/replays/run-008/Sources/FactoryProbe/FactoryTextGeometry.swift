// Runtime size divides physical Float32 by Float32 scale before CGFloat conversion,
// then edge snapping multiplies in CGFloat (Double on Windows). Preserve that route.
// Unknown fractional origin permits floor(d)/ceil(d); integer d also permits d+1
// when nearest-away half ties cross zero. Observed snapped edges must cross then.
func factorySnappedExtentCanMatch(_ measured: Float, _ snapped: Float, origin: Float = 0, scale: Float = 1) -> Bool {
    guard measured.isFinite, snapped.isFinite, origin.isFinite, scale.isFinite,
          scale > 0, measured >= 0, snapped >= 0, snapped == snapped.rounded(),
          origin == origin.rounded() else { return false }
    let extent = Double(measured / scale) * Double(scale)
    guard extent.isFinite else { return false }
    let output = Double(snapped)
    if output == extent.rounded(.down) || output == extent.rounded(.up) { return true }
    return extent >= 1 && extent == extent.rounded() && output == extent + 1 &&
      origin < 0 && origin + snapped > 0
}
