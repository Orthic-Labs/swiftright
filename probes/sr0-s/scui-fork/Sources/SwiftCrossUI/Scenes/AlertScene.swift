/// A scene that shows a standalone alert.
///
/// The exact behavior of the alert is backend-dependent, but it typically
/// shows up as an application modal, or attaches itself to the app's main
/// window.
public struct AlertScene: Scene {
    public typealias Node = AlertSceneNode

    var title: String
    @Binding var isPresented: Bool
    var actions: [AlertAction]

    /// Creates an alert scene.
    ///
    /// The exact behavior of the alert is backend-dependent, but it typically
    /// shows up as an application modal, or attaches itself to the app's main
    /// window.
    ///
    /// - Parameters:
    ///   - title: The alert's title.
    ///   - isPresented: A binding to a `Bool` that controls whether the alert
    ///     is presented.
    ///   - actions: The alert's actions.
    public init(
        _ title: String,
        isPresented: Binding<Bool>,
        @AlertActionsBuilder actions: () -> [AlertAction]
    ) {
        self.title = title
        self._isPresented = isPresented
        self.actions = actions()
    }
}

/// The scene graph node for ``AlertScene``.
public final class AlertSceneNode: SceneGraphNode {
    public typealias NodeScene = AlertScene

    private var scene: AlertScene
    private var alert: Any?

    public init<Backend: BaseAppBackend>(
        from scene: AlertScene,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        self.scene = scene
    }

    public func updateNode(
        _ newScene: NodeScene?,
        environment: EnvironmentValues
    ) -> SceneNodeUpdateResult {
        if let newScene {
            self.scene = newScene
        }

        return .leafScene()
    }

    public func update<Backend: BaseAppBackend>(
        backend: Backend,
        environment: EnvironmentValues
    ) {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.Alerts>(_ backend: NewBackend) {
        if scene.isPresented, alert == nil {
            let alert = backend.createAlert()
            backend.updateAlert(
                alert,
                title: scene.title,
                actionLabels: scene.actions.map(\.label),
                environment: environment
            )
            backend.showAlert(alert, window: nil) { responseId in
                self.alert = nil
                self.scene.isPresented = false
                self.scene.actions[responseId].action()
            }

            self.alert = alert
        } else if !scene.isPresented, let alert {
            backend.dismissAlert(alert as! NewBackend.Alert, window: nil)
            self.alert = nil
        }
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.Alerts else {
            fatalError("backend does not implement BackendFeatures.Alerts")
        }
        return __castBackend1(__castedBackend1)
    }
}
