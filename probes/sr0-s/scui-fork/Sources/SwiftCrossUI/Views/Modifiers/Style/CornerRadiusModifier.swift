extension View {
    public func cornerRadius(_ radius: Int) -> some View {
        CornerRadiusModifier(content: self, cornerRadius: radius)
    }
}

struct CornerRadiusModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var cornerRadius: Int

    var body: TupleView1<Content> { content }

    typealias Children = TupleView1<Content>.Children

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.CornerRadius>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createCornerRadiusContainer(wrapping: body.asWidget(children, backend: backend))
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.CornerRadius else {
            fatalError("backend does not implement BackendFeatures.CornerRadius")
        }
        return __castBackend1(__castedBackend1) as! Backend.Widget
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.CornerRadius>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.setCornerRadius(of: widget, to: cornerRadius)
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.CornerRadius else {
            fatalError("backend does not implement BackendFeatures.CornerRadius")
        }
        return __castBackend2(__castedBackend2)
    }
}
