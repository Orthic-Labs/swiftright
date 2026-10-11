import Foundation

struct R3StyleView: View {
    let variant: Int

    var body: some View {
        let font = variant == 0
            ? Font.custom("ProbeFamily", size: 13)
            : Font.custom("ProbeFamily", size: 14)
        let color: Color = variant == 0 ? .red : .blue
        Text("styled").font(font).foregroundStyle(color)
    }
}

struct R3DefaultView: View {
    var body: some View { Text("default") }
}

struct R3AdditionsView: View {
    let variant: Int

    var body: some View {
        VStack {
            if variant == 0 {
                Circle().fill(.green)
            } else {
                Circle().fill(.blue)
            }
            Image(systemName: "plain")
            Image(systemName: "resized").resizable().scaledToFit()
            R3ToggleView(variant: variant)
        }
    }
}

struct R3ToggleView: View {
    let variant: Int

    @ViewBuilder
    var body: some View {
        if variant == 0 {
            Toggle("switch", isOn: Binding(get: { true }, set: { _ in }))
                .toggleStyle(.switch)
                .labelsHidden()
        } else {
            Toggle("automatic", isOn: Binding(get: { true }, set: { _ in }))
                .toggleStyle(.automatic)
                .labelsHidden()
        }
    }
}

@main
@MainActor
struct R3Controls {
    static func snapshot<V: View>(_ view: V) -> ResolvedNode {
        let graph = Graph(view)
        graph.flush()
        return graph.snapshot()!
    }

    static func first(_ root: ResolvedNode, matching predicate: (ResolvedNode) -> Bool) -> ResolvedNode? {
        if predicate(root) { return root }
        for child in root.children {
            if let found = first(child, matching: predicate) { return found }
        }
        return nil
    }

    static func main() {
        let styleEqualA = first(snapshot(R3StyleView(variant: 0)), matching: { $0.text == "styled" })!
        let styleEqualB = first(snapshot(R3StyleView(variant: 0)), matching: { $0.text == "styled" })!
        let styleUnequal = first(snapshot(R3StyleView(variant: 1)), matching: { $0.text == "styled" })!

        let defaultNode = first(snapshot(R3DefaultView()), matching: { $0.text == "default" })!
        let additionsEqualA = snapshot(R3AdditionsView(variant: 0))
        let additionsEqualB = snapshot(R3AdditionsView(variant: 0))
        let additionsUnequal = snapshot(R3AdditionsView(variant: 1))
        let shapeA = first(additionsEqualA, matching: { $0.kind == "Circle" })!
        let shapeUnequal = first(additionsUnequal, matching: { $0.kind == "Circle" })!
        let plainImage = first(additionsEqualA, matching: { $0.image?.name == "plain" })!
        let resizedImage = first(additionsEqualA, matching: { $0.image?.name == "resized" })!
        let toggleA = first(additionsEqualA, matching: { $0.kind == "Toggle" })!
        let toggleUnequal = first(additionsUnequal, matching: { $0.kind == "Toggle" })!

        let copiedSnapshot = additionsEqualA
        var copiedChildren = copiedSnapshot.children
        let childCountBeforeCopyMutation = copiedChildren.count
        copiedChildren.removeLast()
        let copyRetainedOriginal = additionsEqualA.children.count == childCountBeforeCopyMutation

        print("styleIndependentEqual=\(styleEqualA.style == styleEqualB.style)")
        print("styleIndependentUnequal=\(styleEqualA.style != styleUnequal.style)")
        print("defaultStyleNil=\(defaultNode.style.font == nil && defaultNode.style.foreground == nil)")
        print("additionsIndependentEqual=\(additionsEqualA == additionsEqualB)")
        print("additionsIndependentUnequal=\(additionsEqualA != additionsUnequal)")
        print("shapeIndependentUnequal=\(shapeA != shapeUnequal)")
        print("copyRetainedOriginal=\(copyRetainedOriginal)")
        print("plainImageSizingNil=\(plainImage.imageSizing == nil)")
        print("resizedImageSizingPresent=\(resizedImage.imageSizing != nil)")
        print("toggleStyleEqual=\(toggleA.toggleStyle == "SwitchToggleStyle")")
        print("toggleStyleUnequal=\(toggleA.toggleStyle != toggleUnequal.toggleStyle)")
        print("toggleLabelsHidden=\(toggleA.labelsHidden == true && toggleUnequal.labelsHidden == true)")
        print("customFontFamily=\(styleEqualA.style.font?.metadata?.familyName ?? "nil")")
        print("customForeground=\(String(describing: styleEqualA.style.foreground))")
        print("shapeColor=\(String(describing: shapeA.shape?.paint?.color))")
    }
}
