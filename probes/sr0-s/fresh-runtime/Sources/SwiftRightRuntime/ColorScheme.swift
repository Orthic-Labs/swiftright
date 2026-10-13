import Foundation

// SR1 block 20 (swiftui.color-scheme): `.preferredColorScheme(_:)`, `.environment(\.colorScheme, _)` (the generic environment modifier), `@Environment(\.colorScheme)`
// and the semantic colours (`Color.primary`, `.secondary`, `Color.accentColor`, `.background`). A node's scheme reaches the backend as `ResolvedStyle.colorScheme`;
// the backend resolves semantic colour names with it (SwiftRightHost `HostPaint`, tables measured from SwiftUI on macOS).
// https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)
// https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme

/// What a `.preferredColorScheme` modifier asks of the window it is presented in (nil asks for the host's own scheme back).
struct PreferredSchemeRequest: Equatable {
    let scheme: ColorScheme?
}

private enum PreferredSchemeRequestKey: EnvironmentKey {
    static var defaultValue: PreferredSchemeRequest? { nil }
}

extension EnvironmentValues {
    /// Set by the OUTERMOST `.preferredColorScheme` of a branch; deeper ones do not ask again.
    var preferredColorSchemeRequest: PreferredSchemeRequest? {
        get { self[PreferredSchemeRequestKey.self] }
        set { self[PreferredSchemeRequestKey.self] = newValue }
    }
}

extension View {
    /// Asks for `scheme` for the whole window the view is presented in, as on macOS (where it sets the window's appearance), and gives the view's own subtree that
    /// scheme. nil leaves the host's scheme. Unlike SwiftUI's preference reduction, the outermost modifier of a branch wins and removing the modifier from the tree
    /// does not restore the earlier scheme until a modifier with a different request is evaluated (measured only with a single modifier at the root).
    public func preferredColorScheme(_ scheme: ColorScheme?) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            if environment.preferredColorSchemeRequest == nil { environment.preferredColorSchemeRequest = PreferredSchemeRequest(scheme: scheme) }
            if let scheme { environment.colorScheme = scheme }
        }))
    }
}

/// `ShapeStyle.background`: the window's background colour in the scheme in effect (white light, 30/255 grey dark).
public struct BackgroundStyle: ShapeStyle, Hashable {
    public init() {}
    public var resolvedColor: ResolvedColor { .semantic("background") }
}

extension ShapeStyle where Self == BackgroundStyle {
    public static var background: BackgroundStyle { BackgroundStyle() }
}

extension Color {
    /// The app's accent colour (system blue unless the user changed it; the host resolves it).
    public static var accentColor: Color { Color(semantic: "accentColor") }
}

extension Graph {
    /// Called when a node evaluated its environment modifier: remembers the request of a `.preferredColorScheme` (it is the node that SET the request).
    func noteWindowSchemeRequest(_ node: Node) {
        guard let request = node.environment.preferredColorSchemeRequest, node.inherited.preferredColorSchemeRequest == nil else { return }
        windowSchemeRequest = request
    }

    /// Applied between evaluation rounds: the root environment takes the requested scheme (the base scheme again for nil), which re-evaluates the tree.
    func applyWindowSchemeRequest() {
        guard let request = windowSchemeRequest, let root else { return }
        windowSchemeRequest = nil
        if windowSchemeBase == nil { windowSchemeBase = root.inherited.colorScheme }
        let target = request.scheme ?? windowSchemeBase ?? .light
        guard root.inherited.colorScheme != target else { return }
        setRootEnvironment { $0.colorScheme = target }
    }
}
