import Foundation

// Issue #84 (SR2 S5): modifiers whose effect is on an operating-system surface this runtime does not draw, and the ones that are pure bookkeeping. Each is accepted so SwiftUI
// source builds, with the behaviour stated here:
//   - accessibilityAction: recorded; `Graph.accessibilityActionNames(on:)` lists the names and `performAccessibilityAction(named:on:)` runs one (a host maps its UIA custom
//     actions or the invoke action to these).
//   - textSelection, autocorrectionDisabled, scrollContentBackground, help (HitShapeAndHelp.swift): no effect on layout or painting. Text is not selectable and a TextField does
//     no autocorrection on this platform; a List draws its own background.
//   - Namespace and matchedGeometryEffect: the geometry effect is not modelled (a view that changes place jumps, or follows the surrounding animation); layout is unchanged.
//   - mask: a single Shape mask is a clip to that shape (`clipShape`); any other mask view is not applied.
// Not provided: onDrag / onDrop (they need the operating system's drag and drop and NSItemProvider).

final class AccessibilityActionHook {
    let name: String
    let action: () -> Void
    init(name: String, action: @escaping () -> Void) { self.name = name; self.action = action }
}

/// Apple: https://developer.apple.com/documentation/swiftui/accessibilityactionkind
public struct AccessibilityActionKind: Equatable, Sendable {
    let name: String
    public static let `default` = AccessibilityActionKind(name: "default")
    public static let escape = AccessibilityActionKind(name: "escape")
    public static let magicTap = AccessibilityActionKind(name: "magicTap")
    init(name: String) { self.name = name }
    public init(named name: Text) { self.name = name.string }
}

/// Apple: https://developer.apple.com/documentation/swiftui/textselectability
public protocol TextSelectability { static var allowsSelection: Bool { get } }
public struct EnabledTextSelectability: TextSelectability { public static var allowsSelection: Bool { true } }
public struct DisabledTextSelectability: TextSelectability { public static var allowsSelection: Bool { false } }
extension TextSelectability where Self == EnabledTextSelectability { public static var enabled: EnabledTextSelectability { EnabledTextSelectability() } }
extension TextSelectability where Self == DisabledTextSelectability { public static var disabled: DisabledTextSelectability { DisabledTextSelectability() } }

/// Apple: https://developer.apple.com/documentation/swiftui/namespace
@propertyWrapper
public struct Namespace {
    /// Apple: https://developer.apple.com/documentation/swiftui/namespace/id
    public struct ID: Hashable, Sendable { let raw: UUID }
    private let raw = UUID()
    public init() {}
    public var wrappedValue: ID { ID(raw: raw) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/matchedgeometryproperties
public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let position = MatchedGeometryProperties(rawValue: 1)
    public static let size = MatchedGeometryProperties(rawValue: 2)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:)
    public func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> some View {
        Modified(content: self, spec: .accessibilityAction(AccessibilityActionHook(name: name.string, action: handler)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:)
    public func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping () -> Void) -> some View {
        Modified(content: self, spec: .accessibilityAction(AccessibilityActionHook(name: String(name), action: handler)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/accessibilityaction(_:_:)
    public func accessibilityAction(_ kind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> some View {
        Modified(content: self, spec: .accessibilityAction(AccessibilityActionHook(name: kind.name, action: handler)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/textselection(_:)
    public func textSelection<S: TextSelectability>(_ selectability: S) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/autocorrectiondisabled(_:)
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)
    public func scrollContentBackground(_ visibility: Visibility) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)
    public func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID, properties: MatchedGeometryProperties = .frame, anchor: UnitPoint = .center, isSource: Bool = true) -> some View { self }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/mask(alignment:_:)
    @MainActor public func mask<M: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> M) -> AnyView {
        if let shape = mask() as? any Shape { return AnyView(clip(to: shape)) }
        return AnyView(self)
    }

    @MainActor private func clip<S: Shape>(to shape: S) -> some View { clipShape(shape) }
}

extension Graph {
    private func actionHooks(on id: String) -> [AccessibilityActionHook] {
        guard var n = node(id) else { return [] }
        var hooks: [AccessibilityActionHook] = []
        while true {
            if case .modifier(.accessibilityAction(let h)) = n.kind { hooks.append(h) }
            let kids = childNodes(n)
            guard kids.count == 1, case .modifier = kids[0].kind else { break }
            n = kids[0]
        }
        if case .modifier(.accessibilityAction(let h)) = n.kind, !hooks.contains(where: { $0 === h }) { hooks.append(h) }
        return hooks
    }

    /// The names of the custom accessibility actions on the view node `id` and the modifier chain directly beneath it.
    public func accessibilityActionNames(on id: String) -> [String] { actionHooks(on: id).map(\.name) }

    /// Runs the accessibility action `name` on `id`; returns whether one ran.
    @discardableResult
    public func performAccessibilityAction(named name: String, on id: String) -> Bool {
        guard let hook = actionHooks(on: id).first(where: { $0.name == name }) else { return false }
        hook.action(); flush(); return true
    }
}
