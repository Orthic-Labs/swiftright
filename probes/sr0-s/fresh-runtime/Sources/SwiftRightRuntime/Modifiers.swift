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
        Modified(content: self, spec: .task(priority, nil, action))
    }

    /// As SwiftUI `task(id:)`: starts on appear, and cancels and restarts when `value` changes. The
    /// previous run's commits are rejected once it has been replaced.
    public func task<T: Equatable>(
        id value: T,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        Modified(content: self, spec: .task(priority, AnyEquatable(value), action))
    }

    /// Gives focus to this view while `binding` names `value`. Removing the view clears the focus
    /// (when it names `value`), as on the Mac oracle.
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        let link = FocusLink(
            isFocused: { binding.wrappedValue == value },
            focus: { binding.assign(value) },
            release: { if binding.wrappedValue == value { binding.reset() } }
        )
        return Modified(content: self, spec: .focus(link))
    }

    /// Multiplies this view's opacity. Changes animate under an animated transaction.
    public func opacity(_ value: Double) -> some View {
        Modified(content: self, spec: .opacity(value))
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
