/// A type of tap gesture.
public struct TapGesture: Sendable, Hashable {
    @_spi(Backends) public var kind: TapGestureKind

    /// The idiomatic "primary" interaction for the device, such as a left-click
    /// with the mouse or normal tap on a touch screen.
    public static let primary = TapGesture(kind: .primary)
    /// The idiomatic "secondary" interaction for the device, such as a
    /// right-click with the mouse or long press on a touch screen.
    public static let secondary = TapGesture(kind: .secondary)
    /// A long press of the same interaction type as ``primary``.
    ///
    /// May be equivalent to ``secondary`` on some backends, particularly on
    /// mobile devices.
    public static let longPress = TapGesture(kind: .longPress)

    @_spi(Backends) public enum TapGestureKind: Hashable, Sendable {
        case primary
        case secondary
        case longPress
    }
}

extension View {
    /// Adds an action to perform when the user taps or clicks this view.
    ///
    /// Any tappable elements within the view will no longer be tappable with
    /// the same gesture type.
    ///
    /// - Parameters:
    ///   - gesture: The type of gesture to listen for.
    ///   - action: The action to perform.
    public func onTapGesture(
        gesture: TapGesture = .primary,
        perform action: @escaping () -> Void
    ) -> some View {
        OnTapGestureModifier(body: TupleView1(self), gesture: gesture, action: action)
    }

    /// Adds an action to run when this view is clicked. Any clickable elements
    /// within the view will no longer be clickable.
    @available(*, deprecated, renamed: "onTapGesture(gesture:perform:)")
    public func onClick(perform action: @escaping () -> Void) -> some View {
        onTapGesture(perform: action)
    }
}

struct OnTapGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var gesture: TapGesture
    var action: () -> Void

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
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.TapGestures>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createTapGestureTarget(wrapping: children.child0.widget.into(), gesture: gesture)
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.TapGestures else {
            fatalError("backend does not implement BackendFeatures.TapGestures")
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
        children: TupleView1<Content>.Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.TapGestures>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.updateTapGestureTarget(
            widget,
            gesture: gesture,
            environment: environment,
            action: action
        )
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.TapGestures else {
            fatalError("backend does not implement BackendFeatures.TapGestures")
        }
        return __castBackend2(__castedBackend2)
    }
}
