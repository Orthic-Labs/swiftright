import Foundation

// Issue #60 (SR1 backlog), first pass: `.sheet(isPresented:onDismiss:content:)`, `.sheet(item:onDismiss:content:)` and `@Environment(\.dismiss)`.
//
// ADAPTATION: a SwiftUI sheet is its own panel attached to the window. This runtime has one window and no window-level modal layer, so a sheet is presented as an
// OVERLAY LAYER on the view the modifier is attached to: a dimming scrim covering that view's frame and, centred on its top edge (where macOS drops a sheet from),
// the sheet's content at its ideal size (`fixedSize()`, as a sheet takes its content's size) on the window background with 10 pt rounded corners. While the sheet is
// up the covered view takes no pointer hits (`allowsHitTesting(false)`), so the sheet is modal for the pointer. Attach `.sheet` to the window's root view to cover the
// whole window; on a small view (a Button) the layer covers only that view and the panel is centred on its top edge.
// Not modelled: keyboard focus stays reachable in the covered view (Tab can still reach it); Escape does not dismiss; there is no presentation animation, no drop
// shadow, no detents, and the scrim opacity (0.2 black) and corner radius (10) are guesses, not measured on macOS 27.
// `onDismiss` runs when `isPresented` goes from true to false, however that happens (the content's `dismiss()`, a button writing the binding, the owner).

/// Apple: https://developer.apple.com/documentation/swiftui/dismissaction
public struct DismissAction {
    let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    /// Dismisses the sheet or pops the pushed screen the calling view is in; does nothing elsewhere.
    /// Apple: https://developer.apple.com/documentation/swiftui/dismissaction/callasfunction()
    @MainActor public func callAsFunction() {
        perform()
    }
}

private enum DismissActionKey: EnvironmentKey {
    static var defaultValue: DismissAction { DismissAction(perform: {}) }
}

extension EnvironmentValues {
    /// Dismisses the presentation (a sheet) or the pushed screen (a NavigationStack) the view is in. Outside both it does nothing.
    /// Apple: https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}

enum SheetMetrics {
    /// Guess: black at 20%.
    static let scrimOpacity = 0.2
    /// Guess: macOS sheets round at about 10 pt.
    static let cornerRadius: CGFloat = 10
}

/// The scrim and the panel of a presented sheet.
struct SheetPanel<Content: View>: View {
    let content: Content
    let dismiss: @MainActor @Sendable () -> Void

    @MainActor var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(SheetMetrics.scrimOpacity)
            content
                .environment(\.dismiss, DismissAction(perform: dismiss))
                .fixedSize()
                .background(BackgroundStyle())
                .clipShape(RoundedRectangle(cornerRadius: SheetMetrics.cornerRadius))
        }
    }
}

struct BoolSheetHost<Base: View, Sheet: View>: View {
    let base: Base
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheet: () -> Sheet

    @MainActor var body: some View {
        let presented = isPresented.wrappedValue
        base
            .allowsHitTesting(!presented)
            .overlay(alignment: .top) {
                if presented {
                    SheetPanel(content: sheet(), dismiss: { isPresented.wrappedValue = false })
                }
            }
            .onChange(of: presented) { old, new in
                if old && !new { onDismiss?() }
            }
    }
}

struct ItemSheetHost<Base: View, Item: Identifiable, Sheet: View>: View {
    let base: Base
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet

    @MainActor var body: some View {
        let current = item.wrappedValue
        base
            .allowsHitTesting(current == nil)
            .overlay(alignment: .top) {
                if let current {
                    SheetPanel(content: sheet(current), dismiss: { item.wrappedValue = nil })
                }
            }
            .onChange(of: current != nil) { old, new in
                if old && !new { onDismiss?() }
            }
    }
}

extension View {
    /// Presents `content` as a modal layer over this view while `isPresented` is true (see the file header for how this differs from a window-level sheet).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        BoolSheetHost(base: self, isPresented: isPresented, onDismiss: onDismiss, sheet: content)
    }

    /// Presents `content(item)` while `item` is non-nil; the content's `dismiss()` (or a write of nil) dismisses it.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:)
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        ItemSheetHost(base: self, item: item, onDismiss: onDismiss, sheet: content)
    }
}
