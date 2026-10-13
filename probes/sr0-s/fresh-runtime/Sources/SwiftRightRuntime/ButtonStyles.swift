import Foundation

/// Marker for Button style selection metadata. Apple: https://developer.apple.com/documentation/swiftui/buttonstyle
/// The runtime records the selection (the layout depends on it) and the host draws it.
public protocol ButtonStyle: Sendable {}

/// `.automatic`: the platform default, which on macOS is the bordered push button.
public struct DefaultButtonStyle: ButtonStyle { public init() {} }
/// `.bordered`: a bordered push button.
public struct BorderedButtonStyle: ButtonStyle { public init() {} }
/// `.borderedProminent`: a push button filled with the accent colour.
public struct BorderedProminentButtonStyle: ButtonStyle { public init() {} }
/// `.borderless`: the label alone, without chrome.
public struct BorderlessButtonStyle: ButtonStyle { public init() {} }
/// `.plain`: the label alone, in the colour the label gives itself.
public struct PlainButtonStyle: ButtonStyle { public init() {} }

public extension ButtonStyle where Self == DefaultButtonStyle { static var automatic: DefaultButtonStyle { DefaultButtonStyle() } }
public extension ButtonStyle where Self == BorderedButtonStyle { static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
public extension ButtonStyle where Self == BorderedProminentButtonStyle { static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() } }
public extension ButtonStyle where Self == BorderlessButtonStyle { static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() } }
public extension ButtonStyle where Self == PlainButtonStyle { static var plain: PlainButtonStyle { PlainButtonStyle() } }

/// The look a Button resolves to (the default style and an unset style are the bordered push button on macOS).
public enum ButtonLook: Equatable, Sendable {
    case bordered, prominent, borderless, plain

    /// `style` is `ResolvedNode.buttonStyle` (the style's type name), nil when no `.buttonStyle` applies. `isDefaultAction` is a Button under
    /// `.keyboardShortcut(.defaultAction)`: macOS draws it as the prominent push button (measured), whatever the automatic style says.
    public init(style: String?, isDefaultAction: Bool = false) {
        switch style {
        case "BorderedProminentButtonStyle": self = .prominent
        case "BorderlessButtonStyle": self = .borderless
        case "PlainButtonStyle": self = .plain
        case "BorderedButtonStyle": self = .bordered
        default: self = isDefaultAction ? .prominent : .bordered
        }
    }

    /// True for the looks that draw a push-button body (and pad the label inside it).
    public var hasBody: Bool { self == .bordered || self == .prominent }
}
