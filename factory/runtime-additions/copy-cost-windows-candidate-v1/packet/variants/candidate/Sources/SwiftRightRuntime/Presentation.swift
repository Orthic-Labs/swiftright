import Foundation

// Menus, context menus, alerts and confirmation dialogs are model nodes. The runtime owns presentation
// state (the `isPresented` binding) and action dispatch; the backend decides how to show them.
// https://developer.apple.com/documentation/swiftui/menu
// https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)
// https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)
// https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
//
// Menu, alert and dialog content is walked as views. Primitives (Button, Text, Divider, Menu, modifiers) are
// read exactly. Custom View types are evaluated outside the graph, so their own @State is not the node's
// (a documented gap in RESULT.md).

/// Button-like views: their label, action and role.
@MainActor
protocol ButtonView {
    var buttonLabel: any View { get }
    var buttonAction: () -> Void { get }
    var buttonRole: ButtonRole? { get }
}

/// Menu views: their title label and their item content.
@MainActor
protocol MenuView {
    var menuLabel: any View { get }
    var menuContent: any View { get }
}

/// Views that carry an accessibility title (TextField, Toggle).
@MainActor
protocol LabeledControl {
    var titleView: any View { get }
}

/// Modifier wrappers, so the walker can see their content and their environment change.
@MainActor
protocol WrappedModifier {
    var modifierInner: any View { get }
    var modifierSpec: ModifierSpec { get }
}

extension Button: @MainActor ButtonView {
    var buttonLabel: any View { label }
    var buttonAction: () -> Void { action }
    var buttonRole: ButtonRole? { role }
}

extension Menu: @MainActor MenuView {
    var menuLabel: any View { label }
    var menuContent: any View { content }
}

extension TextField: @MainActor LabeledControl {
    var titleView: any View { label }
}

extension Modified: @MainActor WrappedModifier {
    var modifierInner: any View { content }
    var modifierSpec: ModifierSpec { spec }
}

/// One item of a menu or of an alert's actions, as the walker extracted it at evaluation.
struct MenuEntry {
    enum Kind {
        case action(() -> Void)
        case divider
        case submenu([MenuEntry])
    }

    let title: String
    let kind: Kind
    let isDisabled: Bool
    let role: ButtonRole?
}

/// Walks view content for menu items and for text. Pure view evaluation; it never touches graph nodes.
@MainActor
enum ViewWalk {
    static func entries(_ view: any View, environment: EnvironmentValues) -> [MenuEntry] {
        if view is EmptyView { return [] }
        let mirror = Mirror(reflecting: view)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first?.value as? any View else { return [] }
            return entries(child, environment: environment)
        }
        if view is Divider {
            return [MenuEntry(title: "", kind: .divider, isDisabled: false, role: nil)]
        }
        if view is Text { return [] }  // bare text is a label, not an item
        if let button = view as? ButtonView {
            return [MenuEntry(
                title: plainText(button.buttonLabel),
                kind: .action(button.buttonAction),
                isDisabled: !environment.isEnabled,
                role: button.buttonRole
            )]
        }
        if let menu = view as? MenuView {
            return [MenuEntry(
                title: plainText(menu.menuLabel),
                kind: .submenu(entries(menu.menuContent, environment: environment)),
                isDisabled: !environment.isEnabled,
                role: nil
            )]
        }
        if let wrapped = view as? WrappedModifier {
            var inner = environment
            if case .environment(let apply) = wrapped.modifierSpec { apply(&inner) }
            return entries(wrapped.modifierInner, environment: inner)
        }
        if let container = view as? ViewContainer {
            return container.parts().flatMap { entries($0.1, environment: environment) }
        }
        if let primitive = view as? PrimitiveView {
            return primitive.nodeContent.map { entries($0, environment: environment) } ?? []
        }
        return entries(view.evaluateBody(), environment: environment)
    }

    static func texts(_ view: any View) -> [String] {
        if let text = view as? Text { return [text.string] }
        if view is EmptyView || view is Divider { return [] }
        let mirror = Mirror(reflecting: view)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first?.value as? any View else { return [] }
            return texts(child)
        }
        if let button = view as? ButtonView { return texts(button.buttonLabel) }
        if let labeled = view as? LabeledControl { return texts(labeled.titleView) }
        if let wrapped = view as? WrappedModifier { return texts(wrapped.modifierInner) }
        if let container = view as? ViewContainer { return container.parts().flatMap { texts($0.1) } }
        if let primitive = view as? PrimitiveView {
            return primitive.nodeContent.map { texts($0) } ?? []
        }
        return texts(view.evaluateBody())
    }

    static func plainText(_ view: any View) -> String {
        texts(view).joined(separator: " ")
    }
}

/// Kind of a presented modal node.
enum PresentationKind: Sendable {
    case alert
    case confirmationDialog
}

/// Payload of `.alert` or `.confirmationDialog`, captured by the modifier.
struct PresentationPayload {
    let kind: PresentationKind
    let title: String
    let isPresented: Binding<Bool>
    let visibility: Visibility
    let actions: any View
    let message: (any View)?
}

/// Presentation state of a node while `isPresented` is true. Recomputed at each evaluation.
struct PresentedModel {
    let kind: PresentationKind
    let title: String
    let message: String?
    let visibility: Visibility
    let actions: [MenuEntry]
    let isPresented: Binding<Bool>

    @MainActor
    init(payload: PresentationPayload, environment: EnvironmentValues) {
        kind = payload.kind
        title = payload.title
        message = payload.message.map { ViewWalk.plainText($0) }
        visibility = payload.visibility
        actions = ViewWalk.entries(payload.actions, environment: environment)
        isPresented = payload.isPresented
    }
}

// MARK: - Resolved (commit) values

/// Kind of a resolved menu item.
public enum MenuItemKind: String, Hashable, Sendable {
    case action
    case divider
    case submenu
}

public struct ResolvedMenuItem: Equatable, Sendable {
    public let title: String
    public let kind: MenuItemKind
    public let isDisabled: Bool
    public let children: [ResolvedMenuItem]
}

public struct ResolvedPresentationAction: Equatable, Sendable {
    public let title: String
    public let role: ButtonRole?
    public let isDisabled: Bool
}

public struct ResolvedPresentation: Equatable, Sendable {
    /// "alert" or "confirmationDialog".
    public let kind: String
    public let title: String
    public let message: String?
    /// Title visibility of a confirmation dialog; nil for alerts.
    public let titleVisibility: Visibility?
    public let actions: [ResolvedPresentationAction]
}

func resolveMenu(_ entries: [MenuEntry]) -> [ResolvedMenuItem] {
    entries.map { entry in
        switch entry.kind {
        case .action:
            return ResolvedMenuItem(title: entry.title, kind: .action, isDisabled: entry.isDisabled, children: [])
        case .divider:
            return ResolvedMenuItem(title: "", kind: .divider, isDisabled: false, children: [])
        case .submenu(let items):
            return ResolvedMenuItem(
                title: entry.title,
                kind: .submenu,
                isDisabled: entry.isDisabled,
                children: resolveMenu(items)
            )
        }
    }
}

func resolvePresentation(_ model: PresentedModel) -> ResolvedPresentation {
    ResolvedPresentation(
        kind: model.kind == .alert ? "alert" : "confirmationDialog",
        title: model.title,
        message: model.message,
        titleVisibility: model.kind == .confirmationDialog ? model.visibility : nil,
        actions: model.actions.map {
            ResolvedPresentationAction(title: $0.title, role: $0.role, isDisabled: $0.isDisabled)
        }
    )
}

// MARK: - Views

/// A menu: the label is drawn in place; the items are a model, not laid-out children.
@MainActor
public struct Menu<Label: View, Content: View>: View, PrimitiveView {
    let content: Content
    let label: Label

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .menu }
    var nodeContent: (any View)? { label }
}

extension Menu where Label == Text {
    public init(_ titleKey: String, @ViewBuilder content: () -> Content) {
        let label: () -> Text = { Text(titleKey) }
        self.init(content: content, label: label)
    }
}

extension View {
    /// Attaches a context menu. Its items are a model on this node (see `Graph.performMenuItem`).
    public func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        Modified(content: self, spec: .contextMenu(menuItems()))
    }

    /// Presents an alert while `isPresented` is true. The runtime lists the actions; a backend shows them and
    /// reports the choice through `Graph.performPresentationAction`.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)
    public func alert<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        Modified(content: self, spec: .presentation(PresentationPayload(
            kind: .alert,
            title: title,
            isPresented: isPresented,
            visibility: .automatic,
            actions: actions(),
            message: message()
        )))
    }

    /// Presents a confirmation dialog while `isPresented` is true.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        Modified(content: self, spec: .presentation(PresentationPayload(
            kind: .confirmationDialog,
            title: title,
            isPresented: isPresented,
            visibility: titleVisibility,
            actions: actions(),
            message: message()
        )))
    }
}

// MARK: - Graph dispatch

extension Graph {
    /// Runs the action at `path` in a node's menu (context menu or Menu). Each index descends into a submenu;
    /// the last index must name an enabled action. Returns false otherwise.
    @discardableResult
    public func performMenuItem(_ nodeID: String, path: [Int]) -> Bool {
        guard let target = node(nodeID), let entries = target.menuEntries, !path.isEmpty else { return false }
        var current = entries
        for index in path.dropLast() {
            guard current.indices.contains(index), case .submenu(let items) = current[index].kind else { return false }
            current = items
        }
        guard let last = path.last, current.indices.contains(last), !current[last].isDisabled,
              case .action(let run) = current[last].kind else { return false }
        run()
        return true
    }

    /// Runs the enabled action at `index` of a presented alert or dialog, then dismisses it (SwiftUI dismisses on
    /// any action). Returns false when nothing is presented or the action is disabled.
    @discardableResult
    public func performPresentationAction(_ nodeID: String, index: Int) -> Bool {
        guard let target = node(nodeID), let model = target.presented, model.actions.indices.contains(index) else {
            return false
        }
        let entry = model.actions[index]
        guard !entry.isDisabled, case .action(let run) = entry.kind else { return false }
        run()
        model.isPresented.wrappedValue = false
        return true
    }

    /// Dismisses a presented alert or dialog without running an action (Escape, outside click).
    @discardableResult
    public func dismissPresentation(_ nodeID: String) -> Bool {
        guard let target = node(nodeID), let model = target.presented else { return false }
        model.isPresented.wrappedValue = false
        return true
    }
}
