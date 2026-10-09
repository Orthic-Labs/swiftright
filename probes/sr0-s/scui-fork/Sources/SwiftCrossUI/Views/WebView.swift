import Foundation

/// A web view.
@available(tvOS, unavailable)
public struct WebView: ElementaryView {
    /// The ideal size of a WebView.
    private static let idealSize = ViewSize(10, 10)

    @State var currentURL: URL?
    @Binding var url: URL

    /// Creates a web view.
    ///
    /// - Parameter url: A binding to the web view's URL.
    public init(_ url: Binding<URL>) {
        _url = url
    }

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.WebViews>(_ backend: NewBackend) -> NewBackend.Widget {
        return backend.createWebView()
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.WebViews else {
            fatalError("backend does not implement BackendFeatures.WebViews")
        }
        return __castBackend1(__castedBackend1) as! Backend.Widget
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = proposedSize.replacingUnspecifiedDimensions(by: Self.idealSize)
        return ViewLayoutResult
            .leafView(size: size)
            .with(\.isNeverFocusable, false)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.WebViews>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        if url != currentURL {
            backend.navigateWebView(widget, to: url)
            currentURL = url
        }
        backend.updateWebView(widget, environment: environment) { destination in
            currentURL = destination
            url = destination
        }
        backend.setSize(of: widget, to: layout.size.vector)
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.WebViews else {
            fatalError("backend does not implement BackendFeatures.WebViews")
        }
        return __castBackend2(__castedBackend2)
    }
}
