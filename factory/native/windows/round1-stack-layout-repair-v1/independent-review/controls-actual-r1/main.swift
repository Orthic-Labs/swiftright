// Prepared shared-function controls; no bridge/runtime/window calls.
for kind in ["VStack", "HStack", "ZStack", "Overlay", "Layout", "Group", "EmptyView", "Spacer"] {
    precondition(factoryIsStructuralContainer(kind), "structural container rejected")
}
for kind in ["Text", "Image", "Button", "Color", "Rectangle", "Circle", "ScrollView", "Toggle", "OverlayFake", "overlay", ""] {
    precondition(!factoryIsStructuralContainer(kind), "paint/provider kind treated as structural")
}
print("FactoryContainer controls passed")
