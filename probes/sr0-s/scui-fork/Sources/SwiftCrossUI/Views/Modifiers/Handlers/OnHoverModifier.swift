extension View {
    /// Adds an action to perform when the user's pointer enters/leaves this
    /// view.
    ///
    /// - Parameter action: The action to perform when the hover state changes.
    ///   Receives a `Bool` parameter indicated whether the pointer entered or
    ///   left the view.
    public func onHover(
        perform action: @escaping (_ hovering: Bool) -> Void
    ) -> some View {
        OnHoverModifier(body: TupleView1(self), action: action)
    }
}

struct OnHoverModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var action: (Bool) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.HoverGestures>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createHoverTarget(wrapping: children.child0.widget.into())
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.HoverGestures else {
            fatalError("backend does not implement BackendFeatures.HoverGestures")
        }
        return __castBackend1(__castedBackend1) as! Backend.Widget
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.HoverGestures>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        let size = children.child0.commit().size.vector
        backend.setSize(of: widget, to: size)
        backend.updateHoverTarget(
            widget,
            environment: environment,
            action: action
        )
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.HoverGestures else {
            fatalError("backend does not implement BackendFeatures.HoverGestures")
        }
        return __castBackend2(__castedBackend2)
    }
}
