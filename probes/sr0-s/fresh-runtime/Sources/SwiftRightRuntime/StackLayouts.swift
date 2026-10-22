import Foundation

// Issue #84 (SR2 S5): LazyHStack, HStackLayout / VStackLayout / ZStackLayout and AnyLayout.
//   - LazyHStack realizes every child (as LazyVStack does) and is an HStack for layout.
//   - `HStackLayout(alignment:spacing:) { ... }` builds the same container `HStack` does (the stack algorithm is not duplicated as a `Layout`): its callAsFunction returns the
//     HStack. The `Layout` witnesses below exist so the type conforms (a stack placed by hand: children in a row, centred, 8 pt apart) and are not used by that route.
//   - `AnyLayout(layout) { ... }` builds the container of the layout it wraps, so a Layout switch between stacks is a new container: state of the children does not carry across
//     the switch (SwiftUI keeps it), counted.

/// Apple: https://developer.apple.com/documentation/swiftui/lazyhstack
public struct LazyHStack<Content: View>: View, PrimitiveView {
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        { var spec = StackSpec(name: "LazyHStack", axis: .horizontal, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false); spec.spacingIsDefault = spacing == nil
          if alignment.isCustom { spec.customGuide = .v(alignment) }
          return .stack(spec) }()
    }
    var nodeContent: (any View)? { content }
}

/// A layout that is one of the built-in stacks.
@MainActor protocol StackLayoutBuilding {
    func build(_ content: AnyView) -> AnyView
}

@MainActor private func stackedByHand(_ subviews: Subviews, horizontal: Bool, spacing: CGFloat) -> (sizes: [LayoutSize], total: LayoutSize) {
    var sizes: [LayoutSize] = []
    for sub in subviews { sizes.append(sub.sizeThatFits(.unspecified)) }
    var main: CGFloat = 0, cross: CGFloat = 0
    for size in sizes {
        main += horizontal ? size.width : size.height
        cross = max(cross, horizontal ? size.height : size.width)
    }
    main += spacing * CGFloat(max(0, sizes.count - 1))
    let total: LayoutSize = horizontal ? LayoutSize(width: main, height: cross) : LayoutSize(width: cross, height: main)
    return (sizes, total)
}

/// Apple: https://developer.apple.com/documentation/swiftui/hstacklayout
public struct HStackLayout: Layout, StackLayoutBuilding {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize { stackedByHand(subviews, horizontal: true, spacing: spacing ?? 8).total }
    public func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.origin.x
        for (sub, size) in zip(subviews, stackedByHand(subviews, horizontal: true, spacing: spacing ?? 8).sizes) {
            sub.place(at: LayoutPoint(x: x, y: bounds.origin.y + (bounds.size.height - size.height) / 2), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + (spacing ?? 8)
        }
    }
    @MainActor public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> HStack<Content> { HStack(alignment: alignment, spacing: spacing, content: content) }
    func build(_ content: AnyView) -> AnyView { AnyView(HStack(alignment: alignment, spacing: spacing) { content }) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/vstacklayout
public struct VStackLayout: Layout, StackLayoutBuilding {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize { stackedByHand(subviews, horizontal: false, spacing: spacing ?? 8).total }
    public func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.origin.y
        for (sub, size) in zip(subviews, stackedByHand(subviews, horizontal: false, spacing: spacing ?? 8).sizes) {
            sub.place(at: LayoutPoint(x: bounds.origin.x + (bounds.size.width - size.width) / 2, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            y += size.height + (spacing ?? 8)
        }
    }
    @MainActor public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> VStack<Content> { VStack(alignment: alignment, spacing: spacing, content: content) }
    func build(_ content: AnyView) -> AnyView { AnyView(VStack(alignment: alignment, spacing: spacing) { content }) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/zstacklayout
public struct ZStackLayout: Layout, StackLayoutBuilding {
    public var alignment: Alignment
    public init(alignment: Alignment = .center) { self.alignment = alignment }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return LayoutSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }
    public func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            sub.place(at: LayoutPoint(x: bounds.origin.x + (bounds.size.width - size.width) / 2, y: bounds.origin.y + (bounds.size.height - size.height) / 2),
                      proposal: ProposedViewSize(width: size.width, height: size.height))
        }
    }
    @MainActor public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> ZStack<Content> { ZStack(alignment: alignment, content: content) }
    func build(_ content: AnyView) -> AnyView { AnyView(ZStack(alignment: alignment) { content }) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/anylayout
public struct AnyLayout: Layout {
    let make: @MainActor (AnyView) -> AnyView
    let box: any Layout

    public init<L: Layout>(_ layout: L) {
        box = layout
        if let stack = layout as? any StackLayoutBuilding { make = { stack.build($0) } }
        else { make = { content in AnyView(LayoutRoot(layout: layout, content: content)) } }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize { LayoutSize(width: 0, height: 0) }
    public func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {}

    @MainActor public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> AnyView { make(AnyView(content())) }
}
