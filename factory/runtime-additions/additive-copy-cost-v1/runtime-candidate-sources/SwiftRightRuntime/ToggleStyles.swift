import Foundation

/// Marker for Toggle style selection metadata. Rendering remains host-owned.
public protocol ToggleStyle: Sendable {}

/// The default style selected by `.automatic`.
public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
}

/// A switch-style Toggle marker. This runtime records selection metadata only.
public struct SwitchToggleStyle: ToggleStyle {
    public init() {}
}

public extension ToggleStyle where Self == DefaultToggleStyle {
    static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

public extension ToggleStyle where Self == SwitchToggleStyle {
    static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
