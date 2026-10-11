// Nearest-edge snapping loses fractional origin in ResolvedNode.frame. For any
// origin, an extent d can snap only to floor(d) or ceil(d), never round(d) alone.
func factorySnappedExtentCanMatch(_ measured: Float, _ snapped: Float) -> Bool {
    measured.isFinite && snapped.isFinite && measured >= 0 && snapped >= 0 &&
      snapped == snapped.rounded() && (snapped == measured.rounded(.down) || snapped == measured.rounded(.up))
}
