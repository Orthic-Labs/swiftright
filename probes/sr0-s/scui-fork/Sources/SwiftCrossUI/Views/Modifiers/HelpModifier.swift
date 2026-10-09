extension View {
    /// Adds help text to a view using a string that you provide.
    ///
    /// This configures a hover tooltip where applicable, i.e. desktop and
    /// visionOS. When using touch screens, most users will not be able to
    /// access the help text in a simple way, though it can configure the
    /// accessibility hint text.
    public func help(_ text: String) -> some View {
        HelpView(helpText: text, content: self)
    }
}

struct HelpView<Content: View>: View, TypeSafeView {
    var helpText: String
    var content: Content

    var body: TupleView1<Content> { content }

    typealias Children = TupleView1<Content>.Children

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
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.Tooltips>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createTooltipContainer(wrapping: children.child0.widget.into())
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.Tooltips else {
            fatalError("backend does not implement BackendFeatures.Tooltips")
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
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.Tooltips>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.updateTooltipContainer(widget, tooltip: helpText)
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.Tooltips else {
            fatalError("backend does not implement BackendFeatures.Tooltips")
        }
        return __castBackend2(__castedBackend2)
    }
}
