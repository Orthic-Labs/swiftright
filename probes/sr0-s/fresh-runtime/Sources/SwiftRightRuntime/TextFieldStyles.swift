import Foundation

// TextField styles, placeholder, geometry and submit (SR1 block 13, swiftui.textfield). Numbers are measured on macOS 27 SwiftUI
// (`factory/pipeline/blocks-6-10/swiftui.textfield/FACTS.md`): an offscreen NSHostingView at scale 2.5.

/// Marker for TextField style selection metadata. Rendering is host-owned.
public protocol TextFieldStyle: Sendable {}

/// `.automatic`: on macOS the same bezeled field as `.roundedBorder` and `.squareBorder` (measured: identical pixels).
public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
}

public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
}

public struct SquareBorderTextFieldStyle: TextFieldStyle {
    public init() {}
}

/// No bezel: the text alone.
public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
}

public extension TextFieldStyle where Self == DefaultTextFieldStyle {
    static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}

public extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

public extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}

public extension TextFieldStyle where Self == PlainTextFieldStyle {
    static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

/// Geometry of a TextField, in points (macOS: `AppKitTextField` frame and its `NSSimpleLabel`, measured).
public enum TextFieldMetrics {
    public enum Artwork: Equatable, Sendable {
        /// The bezel of `.automatic`, `.roundedBorder` and `.squareBorder`: a 24 pt field whose text sits 4 pt in; the 1 pt border is drawn
        /// outside the frame.
        case bezel
        /// `.plain`: the text alone, 16 pt tall, no inset.
        case plain
    }

    public static let bezelHeight: CGFloat = 24
    public static let bezelTextInset: CGFloat = 4
    public static let plainHeight: CGFloat = 16
    /// The bezel's border width, drawn outside the field frame.
    public static let bezelBorderWidth: CGFloat = 1

    /// The artwork a `.textFieldStyle` selection resolves to. `style` is `ResolvedNode.fieldStyle`, nil when no `.textFieldStyle` applies.
    public static func artwork(forStyle style: String?) -> Artwork {
        style == String(describing: PlainTextFieldStyle.self) ? .plain : .bezel
    }

    /// Horizontal text inset of an artwork.
    public static func textInset(_ artwork: Artwork) -> CGFloat {
        artwork == .bezel ? bezelTextInset : 0
    }
}

/// What triggers `onSubmit`.
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Return in a text input (TextField, SecureField, TextEditor does not submit).
    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

private enum TextFieldStyleKey: EnvironmentKey {
    static var defaultValue: String? { nil }
}

/// The submit actions in effect, outermost modifier first (macOS oracle: an outer `onSubmit` runs before an inner one).
private enum SubmitActionsKey: EnvironmentKey {
    static var defaultValue: [@MainActor () -> Void] { [] }
}

extension EnvironmentValues {
    var textFieldStyleMetadata: String? {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }

    var submitActions: [@MainActor () -> Void] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }
}

extension View {
    /// Records the TextField style; the host draws it. Apple: https://developer.apple.com/documentation/swiftui/view/textfieldstyle(_:)
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        Modified(content: self, spec: .environment({ environment in
            environment.textFieldStyleMetadata = String(describing: S.self)
        }))
    }

    /// Runs `action` when Return submits a text input inside this view. With several `onSubmit` modifiers around one field, the outermost
    /// runs first (macOS oracle). Apple: https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping @MainActor () -> Void) -> some View {
        Modified(content: self, spec: .environment({ environment in
            if triggers.contains(.text) { environment.submitActions.append(action) }
        }))
    }
}

extension Graph {
    /// Return in the TextField `id`. While the field composes, Return commits the composition and submits nothing (an input method consumes
    /// it); otherwise the `onSubmit` actions around the field run, outermost first. Returns true when the key was handled (a composition
    /// committed or an action ran).
    @discardableResult
    public func pressReturn(inTextField id: String) -> Bool {
        guard let target = node(id), case .textField = target.kind, let state = target.textInput, target.environment.isEnabled else { return false }
        if state.composition != nil { return state.unmark() }
        let actions = target.environment.submitActions
        guard !actions.isEmpty else { return false }
        actions.forEach { $0() }
        return true
    }
}
