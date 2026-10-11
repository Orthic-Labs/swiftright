import Foundation

struct MetadataCopyView: View {
    var body: some View {
        VStack {
            Text("default")
            Text("custom-font").font(.custom("ProbeFamily", size: 13)).foregroundStyle(.red)
            Color.blue
            Circle().fill(.green)
            Image(systemName: "plain")
            Image(systemName: "resized").resizable().scaledToFit()
            Toggle("switch", isOn: Binding(get: { true }, set: { _ in }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

@main
@MainActor
struct MetadataCopyProbe {
    static func main() {
        let graph = Graph(MetadataCopyView())
        graph.flush()
        guard let root = graph.snapshot() else {
            print("snapshotPresent=false")
            return
        }
        let copiedSnapshot = root
        var nodes: [ResolvedNode] = []
        func collect(_ node: ResolvedNode) {
            nodes.append(node)
            node.children.forEach(collect)
        }
        collect(root)

        let defaultText = nodes.first { $0.text == "default" }
        let customText = nodes.first { $0.text == "custom-font" }
        let color = nodes.first { $0.kind == "Color" }
        let shape = nodes.first { $0.kind == "Circle" }
        let plainImage = nodes.first { $0.kind == "Image" && $0.image?.name == "plain" }
        let resizedImage = nodes.first { $0.kind == "Image" && $0.image?.name == "resized" }
        let toggle = nodes.first { $0.kind == "Toggle" }
        var mutableImageSizing = resizedImage?.imageSizing
        mutableImageSizing = nil

        print("snapshotPresent=true")
        print("copiedSnapshotEqual=\(copiedSnapshot == root)")
        print("mutableCopiedMetadataDetached=\(resizedImage?.imageSizing != nil && mutableImageSizing == nil)")
        print("defaultFontMetadataNil=\(defaultText?.style.font?.metadata == nil)")
        print("customFontFamily=\(customText?.style.font?.metadata?.familyName ?? "nil")")
        print("customForeground=\(String(describing: customText?.style.foreground))")
        print("color=\(String(describing: color?.color))")
        print("shape=\(String(describing: shape?.shape))")
        print("plainImageSizingNil=\(plainImage?.imageSizing == nil)")
        print("resizedImageSizingPresent=\(resizedImage?.imageSizing != nil)")
        print("toggleStyle=\(toggle?.toggleStyle ?? "nil")")
        print("toggleLabelsHidden=\(String(describing: toggle?.labelsHidden))")
    }
}
