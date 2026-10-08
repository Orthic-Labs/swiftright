import Foundation

// Modifiers are wrapper views. Each one is a graph node whose lifecycle (appear, disappear,
// task, focus, environment override, animation comparison) follows the node's identity.
// Padding is the one modifier with geometry; the others pass their child's geometry through.

struct Modified<Content: View>: View, PrimitiveView {
    let content: Content
    let spec: ModifierSpec

    @MainActor public var body: Never { return fatalError("modifier has no body") }
    var nodeKind: NodeKind { .modifier(spec) }
    var nodeContent: (any View)? { content }
}

extension View {
    /// Insets the view by `length` on the given edges. A nil length uses the fixed default of 16 pt.
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        Modified(content: self, spec: .padding(EdgeInsets(edges, length ?? defaultPaddingLength)))
    }

    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        Modified(content: self, spec: .appear(action ?? {}))
    }

    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        Modified(content: self, spec: .disappear(action ?? {}))
    }

    /// Starts on appear. Cancelled on disappear, and on any change of this node's identity
    /// (for example a ForEach row whose id changes). Results are committed through
    /// `TaskOwner.current?.commit { ... }`, which rejects stale generations.
    public func task(
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        Modified(content: self, spec: .task(priority, action))
    }

    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        Modified(content: self, spec: .focus({ binding.wrappedValue == value }))
    }

    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        Modified(content: self, spec: .animation(AnyEquatable(value), animation))
    }

    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment[keyPath: keyPath] = value
        }))
    }
}
