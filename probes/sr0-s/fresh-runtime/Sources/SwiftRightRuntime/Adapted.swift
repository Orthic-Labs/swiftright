import Foundation

// SR2 block R6 (issue #41, docs/sr2-plan.md): adapted APIs. They compile and keep layout; what they draw on macOS has no Windows counterpart here.
//
//   glassEffect / Glass        Liquid Glass samples the desktop behind the window; Windows has no such material (the Pulse Windows notch is solid,
//                              pulse/docs/settings.md). The modifier draws nothing and changes nothing: the view is drawn as without it.
//                              Mac references for the glass path are recorded in the app's headlessGlass mode (material left out).
//   contentTransition          .numericText rolls the changed digits inside an animation transaction (#55); the other transitions swap at once.

/// Apple: https://developer.apple.com/documentation/swiftui/glass
public struct Glass: Equatable, Sendable {
    let kind: String
    let tintColor: ResolvedColor?
    let isInteractive: Bool

    public static let regular = Glass(kind: "regular", tintColor: nil, isInteractive: false)
    public static let clear = Glass(kind: "clear", tintColor: nil, isInteractive: false)
    public static let identity = Glass(kind: "identity", tintColor: nil, isInteractive: false)

    public func tint(_ color: Color?) -> Glass { Glass(kind: kind, tintColor: color?.resolvedColor, isInteractive: isInteractive) }
    public func interactive(_ isEnabled: Bool = true) -> Glass { Glass(kind: kind, tintColor: tintColor, isInteractive: isEnabled) }
}

extension View {
    /// Adapted (R6): no material on Windows; the view is drawn as without the modifier. Apple: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
    public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View { self }
    public func glassEffect(_ glass: Glass = .regular) -> some View { self }
}

/// Apple: https://developer.apple.com/documentation/swiftui/contenttransition
public struct ContentTransition: Equatable, Sendable {
    let name: String
    let countsDown: Bool
    let value: Double?
    init(name: String, countsDown: Bool = false, value: Double? = nil) { self.name = name; self.countsDown = countsDown; self.value = value }
    public static let identity = ContentTransition(name: "identity")
    public static let opacity = ContentTransition(name: "opacity")
    public static let interpolate = ContentTransition(name: "interpolate")
    public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition(name: "numericText", countsDown: countsDown) }
    public static func numericText(value: Double) -> ContentTransition { ContentTransition(name: "numericText", value: value) }
}

private enum ContentTransitionKey: EnvironmentKey {
    static var defaultValue: ContentTransition { .identity }
}

extension EnvironmentValues {
    var contentTransition: ContentTransition {
        get { self[ContentTransitionKey.self] }
        set { self[ContentTransitionKey.self] = newValue }
    }
}

extension View {
    /// `.numericText` rolls the changed digits of a Text inside an animation transaction (#55, `NumericTextRoll.swift`); the other transitions swap at once.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/contenttransition(_:)
    public func contentTransition(_ transition: ContentTransition) -> some View { environment(\.contentTransition, transition) }
}
