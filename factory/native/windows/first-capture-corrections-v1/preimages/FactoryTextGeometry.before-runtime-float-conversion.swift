// ResolvedNode.frame has lost fractional origin. Nearest-away-from-zero edge
// snapping permits floor(d)/ceil(d); integer d also permits d+1 when half-tied
// endpoints cross zero. Require observed snapped endpoints to cross zero then.
func factorySnappedExtentCanMatch(_ measured: Float, _ snapped: Float, origin: Float = 0) -> Bool {
    guard measured.isFinite, snapped.isFinite, origin.isFinite, measured >= 0,
          snapped >= 0, snapped == snapped.rounded(), origin == origin.rounded() else { return false }
    if snapped == measured.rounded(.down) || snapped == measured.rounded(.up) { return true }
    return measured >= 1 && measured == measured.rounded() && snapped == measured + 1 &&
      origin < 0 && origin + snapped > 0
}
