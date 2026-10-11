import Foundation

struct AdditiveAPIProbeView: View {
    var body: some View {
        VStack {
            Text("styled").font(.custom("Probe", size: 13)).foregroundStyle(.red)
            Color.blue
            Image(systemName: "star").resizable().scaledToFit()
            Toggle("enabled", isOn: Binding(get: { true }, set: { _ in })).labelsHidden()
        }
    }
}

@main
@MainActor
struct AdditiveAPIProbe {
    static func main() {
        let graph = Graph(AdditiveAPIProbeView())
        graph.flush()
        guard let root = graph.snapshot() else { print("root=nil"); return }
        var nodes: [ResolvedNode] = []
        func collect(_ node: ResolvedNode) {
            nodes.append(node)
            node.children.forEach(collect)
        }
        collect(root)
        let styled = nodes.first { $0.text == "styled" }
        let color = nodes.first { $0.kind == "Color" }
        let image = nodes.first { $0.kind == "Image" }
        let toggle = nodes.first { $0.kind == "Toggle" }
        print("nodeCount=\(nodes.count)")
        print("fontMetadata=\(styled?.style.font?.metadata?.familyName ?? "nil")")
        print("foreground=\(String(describing: styled?.style.foreground))")
        print("color=\(String(describing: color?.color))")
        print("imageSizing=\(image?.imageSizing != nil)")
        print("labelsHidden=\(String(describing: toggle?.labelsHidden))")
    }
}
