import Foundation

// Issue #84 (SR2 S5): `.popover(isPresented:attachmentAnchor:arrowEdge:content:)` and the `item:` form. ADAPTATION, as the sheet: there is no window-level popover layer, so the
// popover is an overlay on the view it modifies, outside that view's frame on the side the arrow points away from (`arrowEdge: .top`, the default, puts it below the view;
// `.bottom` above, `.leading` to the right, `.trailing` to the left), centred on the other axis, at its ideal size on the window background with 10 pt rounded corners, a
// hairline border and a soft shadow. The covered view keeps taking hits (a popover is not modal); there is no arrow, no outside-click dismissal, no animation, and the corner
// radius, border and shadow are not measured on macOS 27. `attachmentAnchor` is accepted and ignored (the whole view is the anchor). The content's `dismiss()` closes it.

/// Apple: https://developer.apple.com/documentation/swiftui/popoverattachmentanchor
public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}

struct PopoverPanel<Content: View>: View {
    let content: Content
    let dismiss: @MainActor @Sendable () -> Void

    @MainActor var body: some View {
        content
            .environment(\.dismiss, DismissAction(perform: dismiss))
            .fixedSize()
            .background(BackgroundStyle())
            .clipShape(RoundedRectangle(cornerRadius: SheetMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: SheetMetrics.cornerRadius).stroke(Color(white: 0, opacity: 0.12), lineWidth: 1))
            .shadow(color: Color(white: 0, opacity: 0.25), radius: 8, x: 0, y: 2)
    }
}

extension View {
    @MainActor fileprivate func popoverOverlay<Panel: View>(edge: Edge, @ViewBuilder _ panel: () -> Panel) -> some View {
        switch edge {
        case .top: return AnyView(overlay(alignment: .bottom) { panel().alignmentGuide(.bottom) { $0[.top] } })
        case .bottom: return AnyView(overlay(alignment: .top) { panel().alignmentGuide(.top) { $0[.bottom] } })
        case .leading: return AnyView(overlay(alignment: .trailing) { panel().alignmentGuide(.trailing) { $0[.leading] } })
        case .trailing: return AnyView(overlay(alignment: .leading) { panel().alignmentGuide(.leading) { $0[.trailing] } })
        }
    }
}

struct BoolPopoverHost<Base: View, Pop: View>: View {
    let base: Base
    let isPresented: Binding<Bool>
    let edge: Edge
    let content: () -> Pop

    @MainActor var body: some View {
        base.popoverOverlay(edge: edge) {
            if isPresented.wrappedValue { PopoverPanel(content: content(), dismiss: { isPresented.wrappedValue = false }) }
        }
    }
}

struct ItemPopoverHost<Base: View, Item: Identifiable, Pop: View>: View {
    let base: Base
    let item: Binding<Item?>
    let edge: Edge
    let content: (Item) -> Pop

    @MainActor var body: some View {
        base.popoverOverlay(edge: edge) {
            if let current = item.wrappedValue { PopoverPanel(content: content(current), dismiss: { item.wrappedValue = nil }) }
        }
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)
    public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top,
                                       @ViewBuilder content: @escaping () -> Content) -> some View {
        BoolPopoverHost(base: self, isPresented: isPresented, edge: arrowEdge, content: content)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/popover(item:attachmentanchor:arrowedge:content:)
    public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top,
                                                           @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        ItemPopoverHost(base: self, item: item, edge: arrowEdge, content: content)
    }
}
