import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// Issue #84 (SR2 S5): onDrag / onDrop, as a compile surface plus a host entry point. Dragging between windows or applications is the operating system's: this runtime has no drag
// source session and no drop target registration. `onDrag` is accepted and starts nothing; `onDrop` records its handler, and a host that receives a drop (OLE on Windows) delivers
// it with `Graph.performDrop(atX:y:providers:)`, which runs the handler of the deepest accepting view under the point, and `Graph.dropTargetChanged(atX:y:)` drives `isTargeted`.
// `NSItemProvider` and `UTType` are small stand-ins where the platform's own are missing (Windows): an item provider holds its objects and loads them back.

#if !canImport(AppKit) && !canImport(UIKit)
/// A minimal item provider: holds the objects (or file URLs) a drag carries.
public final class NSItemProvider: @unchecked Sendable {
    public private(set) var items: [Any]
    public init() { items = [] }
    public init(object: Any) { items = [object] }
    public init(contentsOf url: URL?) { items = url.map { [$0] } ?? [] }
    public func hasItemConformingToTypeIdentifier(_ identifier: String) -> Bool { !items.isEmpty }
    public func loadObject<T>(ofClass: T.Type, completionHandler: @escaping (T?, Error?) -> Void) { completionHandler(items.compactMap { $0 as? T }.first, nil) }
}
#endif

#if !canImport(UniformTypeIdentifiers)
/// A small stand-in for the types a drop can ask for.
public struct UTType: Hashable, Sendable {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public static let fileURL = UTType("public.file-url")
    public static let url = UTType("public.url")
    public static let plainText = UTType("public.plain-text")
    public static let text = UTType("public.text")
    public static let image = UTType("public.image")
    public static let data = UTType("public.data")
    public static let item = UTType("public.item")
}
#endif

final class DropHook {
    let types: [String]
    let isTargeted: Binding<Bool>?
    let perform: ([NSItemProvider], CGPoint) -> Bool
    init(types: [String], isTargeted: Binding<Bool>?, perform: @escaping ([NSItemProvider], CGPoint) -> Bool) { self.types = types; self.isTargeted = isTargeted; self.perform = perform }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/ondrag(_:)
    public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)
    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>? = nil, perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        Modified(content: self, spec: .drop(DropHook(types: supportedContentTypes.map(\.identifier), isTargeted: isTargeted, perform: { providers, _ in action(providers) })))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)-5ahl9
    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>? = nil, perform action: @escaping ([NSItemProvider], CGPoint) -> Bool) -> some View {
        Modified(content: self, spec: .drop(DropHook(types: supportedContentTypes.map(\.identifier), isTargeted: isTargeted, perform: action)))
    }
}

extension Graph {
    private func dropNodes() -> [(node: Node, depth: Int)] {
        var out: [(Node, Int)] = []
        func walk(_ n: Node, _ depth: Int) {
            guard n.alive else { return }
            if case .modifier(.drop) = n.kind { out.append((n, depth)) }
            for c in childNodes(n) { walk(c, depth + 1) }
        }
        if let root { walk(root, 0) }
        return out
    }

    private func dropTarget(atX x: CGFloat, y: CGFloat) -> Node? {
        dropNodes().filter { $0.node.frame.minX <= x && x < $0.node.frame.maxX && $0.node.frame.minY <= y && y < $0.node.frame.maxY && $0.node.environment.allowsHitTesting }
            .max(by: { $0.depth < $1.depth })?.node
    }

    /// The drag pointer is over (x, y) (nil: it left the window): `isTargeted` of every drop view is set to whether it is the deepest one under the point.
    public func dropTargetChanged(atX x: CGFloat?, y: CGFloat?) {
        let target = x.flatMap { x in y.flatMap { dropTarget(atX: x, y: $0) } }
        for (n, _) in dropNodes() {
            guard case .modifier(.drop(let hook)) = n.kind, let binding = hook.isTargeted else { continue }
            let want = n === target
            if binding.wrappedValue != want { binding.wrappedValue = want }
        }
        flush()
    }

    /// A drop happened at (x, y) carrying `providers`: the deepest drop view there runs its handler. Returns what the handler returned (false when no view took it).
    @discardableResult
    public func performDrop(atX x: CGFloat, y: CGFloat, providers: [NSItemProvider]) -> Bool {
        defer { dropTargetChanged(atX: nil, y: nil) }
        guard let node = dropTarget(atX: x, y: y), case .modifier(.drop(let hook)) = node.kind else { return false }
        let accepted = hook.perform(providers, CGPoint(x: x - node.frame.minX, y: y - node.frame.minY))
        flush()
        return accepted
    }
}
