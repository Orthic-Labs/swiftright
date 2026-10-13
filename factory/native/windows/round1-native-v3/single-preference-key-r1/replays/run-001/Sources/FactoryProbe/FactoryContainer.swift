// Structural containers use runtime-resolved bounds & original ordered children.
// No paint, semantics, relayout or case-specific substitution.
func factoryIsStructuralContainer(_ kind: String) -> Bool {
    switch kind {
    case "VStack", "HStack", "ZStack", "Overlay", "Layout", "Group", "EmptyView", "Spacer": return true
    default: return false
    }
}
