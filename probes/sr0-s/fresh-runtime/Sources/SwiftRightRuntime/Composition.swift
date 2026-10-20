import Foundation

// SR2 block R1 (issue #36, docs/sr2-plan.md): composition and placement.
//
//   Group            transparent: a modifier on a Group modifies each member (see `Graph.groupModifierChain`).
//   background       a layer sized to the view and painted behind it; layout unchanged.
//   offset           the view paints shifted; its layout frame and the space it takes are unchanged.
//   position         takes the whole proposed space, centres the view at a point of that space.
//   GeometryReader   takes the whole proposal; its content is built from the size layout gives it.
//   allowsHitTesting `false` removes the subtree from pointer hits (host hit targets, tap gestures, hover).
//
// `ViewModifier` and `View.modifier(_:)` already exist (Views.swift); R1 only adds their layout tests.

// MARK: - Group

/// Internal marker so the graph can find a Group under a modifier chain.
protocol GroupView {}

/// Apple: https://developer.apple.com/documentation/swiftui/group
///
/// A Group is transparent: its members are laid out by the parent as if they were direct children (a `VStack` spaces them, an `HStack` runs them along), and a modifier applied
/// to the Group is applied to each member. What is implemented: every modifier (padding, frame, opacity, offset, onAppear, environment values, ...) is distributed over the
/// members, each member getting its own copy, which is SwiftUI's behaviour for layout-neutral and for layout-changing modifiers alike. A modifier chain over a Group returned
/// directly as a `body` is distributed too, and so is `background` (each member gets its own background, sized to that member). Not distributed: `overlay` (it wraps the Group as one view).
public struct Group<Content: View>: View, ViewContainer, GroupView {
    let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("Group has no body") }
    var supportsRefreshSkip: Bool { true }
    @MainActor func parts() -> [(Segment, any View)] { [(.erased, content)] }
}

// MARK: - Hit testing

private enum AllowsHitTestingKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// False inside `.allowsHitTesting(false)`; a descendant cannot turn it back on (SwiftUI cuts hit testing at the ancestor).
    var allowsHitTesting: Bool {
        get { self[AllowsHitTestingKey.self] }
        set { self[AllowsHitTestingKey.self] = newValue }
    }
}

// MARK: - GeometryReader

/// Apple: https://developer.apple.com/documentation/swiftui/coordinatespace
public enum CoordinateSpace: Hashable, @unchecked Sendable {
    case global
    case local
    case named(AnyHashable)
}

/// Apple: https://developer.apple.com/documentation/swiftui/geometryproxy
public struct GeometryProxy {
    /// The size layout gave the reader.
    public let size: CGSize
    let globalOrigin: CGPoint

    init(size: CGSize, globalOrigin: CGPoint) {
        self.size = size
        self.globalOrigin = globalOrigin
    }

    /// No safe area exists in this runtime's windows.
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }

    /// The reader's frame. `.local` is `(0, 0, size)`. `.global` is the origin the reader had in the graph's coordinates when its content was last built (a move
    /// that leaves the size unchanged does not rebuild the content). `.named` is not supported and reads as `.global`.
    public func frame(in space: CoordinateSpace) -> CGRect {
        switch space {
        case .local: return CGRect(origin: .zero, size: size)
        case .global, .named: return CGRect(origin: globalOrigin, size: size)
        }
    }
}

@MainActor
protocol GeometryReading {
    func makeContent(_ proxy: GeometryProxy) -> any View
}

/// Apple: https://developer.apple.com/documentation/swiftui/geometryreader
///
/// Takes all the space it is offered (an unspecified length is 10 pt) and builds its content for that size, which sits at the top-leading corner at its own size. The
/// content is not built before the first layout (nothing appears at a zero size); the layout pass then builds it, in the same flush, and again whenever the size changes.
public struct GeometryReader<Content: View>: View, GeometryReading {
    let content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }
    @MainActor public var body: Never { return fatalError("GeometryReader has no body") }
    @MainActor func makeContent(_ proxy: GeometryProxy) -> any View { content(proxy) }
}

// MARK: - Background

/// A wrapper the graph distributes over the members of a Group base (`Graph.expand`), as SwiftUI applies a modifier on a Group to each member.
@MainActor protocol GroupBaseDistributable {
    var groupBase: any View { get }
    func rewrapped(over member: any View) -> any View
}

struct BackgroundStack<Base: View, Background: View>: View, PrimitiveView, GroupBaseDistributable {
    let base: Base
    let background: Background
    let alignment: Alignment

    var groupBase: any View { base }
    func rewrapped(over member: any View) -> any View { make(member) }
    private func make<M: View>(_ member: M) -> any View { BackgroundStack<M, Background>(base: member, background: background, alignment: alignment) }

    @MainActor public var body: Never { return fatalError("background has no body") }
    var nodeKind: NodeKind {
        var spec = StackSpec(name: "Background", axis: .overlay, cross: .middle, alignment: alignment, spacing: 0, fillsCross: false)
        spec.baseIsLast = true
        return .stack(spec)
    }
    var nodeContent: (any View)? {
        TupleView<(Background, Base)>(value: (background, base), listed: [background, base])
    }
}

extension View {
    /// Draws `background` behind this view, aligned in the view's frame, offered the view's size. This view's size and place are unchanged.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:alignment:)
    @_disfavoredOverload
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
        BackgroundStack(base: self, background: background, alignment: alignment)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(alignment:content:)
    public func background<Background: View>(alignment: Alignment = .center, @ViewBuilder content: () -> Background) -> some View {
        BackgroundStack(base: self, background: content(), alignment: alignment)
    }

    /// Fills the view's frame behind it with `style`. Apple: https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)
    public func background<S: ShapeStyle>(_ style: S) -> some View {
        BackgroundStack(base: self, background: Rectangle().fill(style), alignment: .center)
    }

    /// Fills `shape` (offered the view's size, centred) behind the view. Apple: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T) -> some View {
        BackgroundStack(base: self, background: shape.fill(style), alignment: .center)
    }
}

// MARK: - Offset, position, hit testing

extension View {
    /// Paints this view shifted by (`x`, `y`) points; its layout frame, and the space it takes in its parent, are unchanged. Runtime tap and hover hit testing (`Graph.tapGesture`, `pointerMoved`) follows the painting.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/offset(x:y:)
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        Modified(content: self, spec: .offset(x, y))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/offset(_:)
    public func offset(_ offset: CGSize) -> some View {
        Modified(content: self, spec: .offset(offset.width, offset.height))
    }

    /// Takes all the space it is offered and centres this view at (`x`, `y`) of that space (its own top-leading corner is the origin).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/position(x:y:)
    public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        Modified(content: self, spec: .position(x, y))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/position(_:)
    public func position(_ position: CGPoint) -> some View {
        Modified(content: self, spec: .position(position.x, position.y))
    }

    /// With `false`, this view and its subtree take no pointer hits (taps, hover, host hit targets); layout and painting are unchanged, and accessibility actions still work.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/allowshittesting(_:)
    public func allowsHitTesting(_ enabled: Bool) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.allowsHitTesting = environment.allowsHitTesting && enabled
        }))
    }
}
