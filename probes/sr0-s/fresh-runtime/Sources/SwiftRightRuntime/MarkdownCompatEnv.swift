import Foundation

// Issue #68 pass 3 (MarkdownUI on SwiftRight): environment and preference transforms, `multilineTextAlignment`, `foregroundColor`, `openURL`,
// `ScaledMetric`, and the Text conveniences MarkdownUI's inline renderer needs.

// MARK: - TextAlignment

/// Apple: https://developer.apple.com/documentation/swiftui/textalignment
public enum TextAlignment: Hashable, CaseIterable, Sendable {
    case leading, center, trailing
}

private enum MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

extension EnvironmentValues {
    /// How multi-line text aligns inside its frame. Carried through the environment (blocks read it, as MarkdownUI's `BlockSequence` does);
    /// Text layout and painting still lay lines out leading-aligned, so centre and trailing do not move glyphs yet.
    /// Apple: https://developer.apple.com/documentation/swiftui/environmentvalues/multilinetextalignment
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

extension View {
    /// Sets `multilineTextAlignment` for the views below. Carried only; see the environment value.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/multilinetextalignment(_:)
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}

// MARK: - OpenURLAction

/// Sends a URL to a handler, by default the host's opener. Apple: https://developer.apple.com/documentation/swiftui/openurlaction
public struct OpenURLAction {
    /// What a handler did with a URL. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/result
    public struct Result: Sendable {
        enum Kind: Sendable {
            case handled, discarded
            case systemAction(URL?)
        }
        let kind: Kind
        private init(_ kind: Kind) { self.kind = kind }

        /// The handler opened the URL itself. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/result/handled
        public static let handled = Result(.handled)
        /// The handler dropped the URL; nothing opens. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/result/discarded
        public static let discarded = Result(.discarded)
        /// The host opens the original URL. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/result/systemaction
        public static let systemAction = Result(.systemAction(nil))
        /// The host opens `url` instead. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/result/systemaction(_:)
        public static func systemAction(_ url: URL) -> Result { Result(.systemAction(url)) }
    }

    private final class Hook: @unchecked Sendable {
        private let lock = NSLock()
        private var opener: (@Sendable (URL) -> Bool)?
        func get() -> (@Sendable (URL) -> Bool)? { lock.lock(); defer { lock.unlock() }; return opener }
        func set(_ value: (@Sendable (URL) -> Bool)?) { lock.lock(); defer { lock.unlock() }; opener = value }
    }
    private static let hook = Hook()

    /// The host's way to open a URL (a Windows host registers ShellExecute here); returns whether the URL was opened.
    /// With none registered, a `.systemAction` logs to standard error and opens nothing.
    public static var systemOpener: (@Sendable (URL) -> Bool)? {
        get { hook.get() }
        set { hook.set(newValue) }
    }

    private let handler: (URL) -> Result

    /// Apple: https://developer.apple.com/documentation/swiftui/openurlaction/init(handler:)
    public init(handler: @escaping (URL) -> Result) { self.handler = handler }

    /// Runs the handler for `url`, then the host opener when it answers `.systemAction`. Returns whether the URL was accepted.
    @discardableResult
    func perform(_ url: URL) -> Bool {
        switch handler(url).kind {
        case .handled: return true
        case .discarded: return false
        case .systemAction(let replacement):
            let target = replacement ?? url
            guard let opener = OpenURLAction.systemOpener else {
                FileHandle.standardError.write(Data("openURL: no host opener registered; not opening \(target.absoluteString)\n".utf8))
                return false
            }
            return opener(target)
        }
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/openurlaction/callasfunction(_:)
    public func callAsFunction(_ url: URL) { perform(url) }

    /// `completion` receives whether the URL was accepted. Apple: https://developer.apple.com/documentation/swiftui/openurlaction/callasfunction(_:completion:)
    public func callAsFunction(_ url: URL, completion: @escaping (Bool) -> Void) { completion(perform(url)) }
}

private enum OpenURLKey: EnvironmentKey {
    static var defaultValue: OpenURLAction { OpenURLAction { _ in .systemAction } }
}

extension EnvironmentValues {
    /// The action links and Buttons call to open a URL. Defaults to the host opener (`OpenURLAction.systemOpener`).
    /// Apple: https://developer.apple.com/documentation/swiftui/environmentvalues/openurl
    public var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }
}

// MARK: - Font.TextStyle and ScaledMetric

extension Font {
    /// Apple: https://developer.apple.com/documentation/swiftui/font/textstyle
    public enum TextStyle: Hashable, CaseIterable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }
}

/// A value that scales with Dynamic Type. This runtime has no Dynamic Type, so the value is the base value, whatever `relativeTo` says.
/// Apple: https://developer.apple.com/documentation/swiftui/scaledmetric
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: Sendable where Value: Sendable {
    private let base: Value

    /// Apple: https://developer.apple.com/documentation/swiftui/scaledmetric/init(wrappedvalue:)
    public init(wrappedValue: Value) { base = wrappedValue }

    /// Apple: https://developer.apple.com/documentation/swiftui/scaledmetric/init(wrappedvalue:relativeto:)
    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) { base = wrappedValue }

    public var wrappedValue: Value { base }
}

// MARK: - View transforms

extension View {
    /// Rewrites one environment value for the views below from its current value.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/transformenvironment(_:transform:)
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            var value = environment[keyPath: keyPath]
            transform(&value)
            environment[keyPath: keyPath] = value
        }))
    }

    /// Rewrites the value `key` reduces to over this view's subtree (the key's default when no descendant contributed) before it flows to ancestors.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/transformpreference(_:_:)
    public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void) -> some View {
        Modified(content: self, spec: .preference(PreferenceContribution(transforming: key, callback)))
    }

    /// The deprecated spelling of `foregroundStyle` for a colour; nil restores the default foreground.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/foregroundcolor(_:)
    public func foregroundColor(_ color: Color?) -> some View {
        let resolved = color?.resolvedColor
        return Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.foregroundStyle = resolved
        }))
    }
}

// MARK: - Text conveniences

extension Text {
    /// The characters of `attributedContent`, as plain text: runs, fonts and colours are dropped (the Text node carries one string; #68).
    /// Apple: https://developer.apple.com/documentation/swiftui/text/init(_:)-1jk6v
    public init(_ attributedContent: AttributedString) { self.init(String(attributedContent.characters)) }

    /// An inline image in text. Approximation: the node carries no inline images, so this is empty text and the image is not drawn (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/text/init(_:)-9fztj
    public init(_ image: Image) { self.init("") }

    /// Joins two texts into one string. Approximation: per-segment modifiers are not kept, the result is one run (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/text/+(_:_:)
    public static func + (lhs: Text, rhs: Text) -> Text { Text(lhs.string + rhs.string) }
}

// MARK: - Line spacing (#68)

private enum LineSpacingKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

extension EnvironmentValues {
    /// Apple: https://developer.apple.com/documentation/swiftui/environmentvalues/linespacing
    public var lineSpacing: CGFloat {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }
}

extension View {
    /// Extra space between lines of text. Carried in the environment; Text layout does not apply it yet (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/linespacing(_:)
    public func lineSpacing(_ lineSpacing: CGFloat) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }
}
