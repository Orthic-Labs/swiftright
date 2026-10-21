import Foundation

// MARK: - Text.LineStyle

extension Text {
    /// Apple: https://developer.apple.com/documentation/swiftui/text/linestyle
    public struct LineStyle: Hashable, Sendable {
        /// Apple: https://developer.apple.com/documentation/swiftui/text/linestyle/pattern-swift.struct
        public struct Pattern: Hashable, Sendable {
            let name: String
            public static let solid = Pattern(name: "solid")
            public static let dot = Pattern(name: "dot")
            public static let dash = Pattern(name: "dash")
            public static let dashDot = Pattern(name: "dashDot")
            public static let dashDotDot = Pattern(name: "dashDotDot")
        }

        public let pattern: Pattern
        public let color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// A solid line in the text's colour.
        public static let single = LineStyle()
    }
}

// MARK: - SwiftUI attribute scope

/// The SwiftUI attributes of an `AttributedString` (`AttributeContainer.foregroundColor` and the rest). `Text(AttributedString)` turns each run into a styled Text run
/// (font, foreground and background colour, underline, strikethrough, kern, tracking, baseline offset, link; StyledText.swift) that a host measures and paints (#68).
/// Apple: https://developer.apple.com/documentation/foundation/attributescopes/swiftuiattributes
extension AttributeScopes {
    public struct SwiftUIAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let kern: KerningAttribute
        public let tracking: TrackingAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: AttributeScopes.FoundationAttributes

        public enum FontAttribute: AttributedStringKey {
            public typealias Value = Font
            public static let name = "SwiftUI.Font"
        }
        public enum ForegroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.ForegroundColor"
        }
        public enum BackgroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.BackgroundColor"
        }
        public enum StrikethroughStyleAttribute: AttributedStringKey {
            public typealias Value = Text.LineStyle
            public static let name = "SwiftUI.StrikethroughStyle"
        }
        public enum UnderlineStyleAttribute: AttributedStringKey {
            public typealias Value = Text.LineStyle
            public static let name = "SwiftUI.UnderlineStyle"
        }
        public enum KerningAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.Kern"
        }
        public enum TrackingAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.Tracking"
        }
        public enum BaselineOffsetAttribute: AttributedStringKey {
            public typealias Value = CGFloat
            public static let name = "SwiftUI.BaselineOffset"
        }
    }

    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T {
        self[T.self]
    }
}

// MARK: - Font variants (#68)

extension Font {
    /// The same font with `tag` appended to its identity and its metadata kept. Used for variants the renderer does not yet draw differently.
    private func tagged(_ tag: String, design: Design? = nil, italic: Bool? = nil) -> Font {
        guard let base = metadata else { return Font(id: "\(id)|\(tag)") }
        return Font(id: "\(id)|\(tag)",
                    metadata: Metadata(familyName: base.familyName, pointSize: base.pointSize, weight: base.weight, design: design ?? base.design,
                                       isCustom: base.isCustom, textStyle: base.textStyle, width: base.width, isEmphasized: base.isEmphasized,
                                       monospacedDigit: base.monospacedDigit, isItalic: italic ?? base.isItalic))
    }

    /// A custom font that does not scale with Dynamic Type (this runtime has no Dynamic Type, so it equals `custom(_:size:)`).
    /// Apple: https://developer.apple.com/documentation/swiftui/font/custom(_:fixedsize:)
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { custom(name, size: fixedSize) }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/monospaced()
    public func monospaced() -> Font { tagged("monospaced", design: .monospaced) }

    /// Carried with the font as `Metadata.isItalic`: a bundled custom font draws its real italic face (#78); a system font's italic is carried and not yet drawn.
    /// Apple: https://developer.apple.com/documentation/swiftui/font/italic()
    public func italic() -> Font { tagged("italic", italic: true) }

    /// Carried with the font; not yet drawn as small capitals (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/font/smallcaps()
    public func smallCaps() -> Font { tagged("smallCaps") }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/lowercasesmallcaps()
    public func lowercaseSmallCaps() -> Font { tagged("lowercaseSmallCaps") }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/uppercasesmallcaps()
    public func uppercaseSmallCaps() -> Font { tagged("uppercaseSmallCaps") }
}

// MARK: - Image additions (#68)

/// Apple: https://developer.apple.com/documentation/swiftui/symbolrenderingmode
public struct SymbolRenderingMode: Hashable, Sendable {
    let name: String
    public static let monochrome = SymbolRenderingMode(name: "monochrome")
    public static let multicolor = SymbolRenderingMode(name: "multicolor")
    public static let hierarchical = SymbolRenderingMode(name: "hierarchical")
    public static let palette = SymbolRenderingMode(name: "palette")
}

extension Image {
    /// Apple: https://developer.apple.com/documentation/swiftui/image/scale
    public enum Scale: Hashable, Sendable { case small, medium, large }

    /// A named asset image; `bundle` is not consulted (assets resolve by name as `init(_:)`) and `label` becomes the accessibility label.
    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(_:bundle:label:)
    nonisolated public init(_ name: String, bundle: Bundle?, label: Text) {
        reference = .named(name)
        labelText = label.string
    }

    /// Decoded pixels with an accessibility label: SwiftUI's `Image(_ cgImage:scale:orientation:label:)` with this runtime's pixel type.
    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(_:scale:orientation:label:)
    nonisolated public init(_ image: RGBAImage, scale: CGFloat, label: Text) {
        reference = .pixels(image, scale: scale > 0 ? scale : 1)
        labelText = label.string
    }

    /// Accepted; symbols draw monochrome in this runtime (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/image/symbolrenderingmode(_:)
    nonisolated public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image { self }
}

extension View {
    /// Accepted; symbol images keep their size in this runtime (#68).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/imagescale(_:)
    public func imageScale(_ scale: Image.Scale) -> some View { self }
}

/// This runtime's SwiftUI attribute keys under a name that does not collide with Apple's SwiftUI scope when both are loaded (Mac tests).
public enum SwiftRightTextAttributes {
    public typealias Kerning = AttributeScopes.SwiftUIAttributes.KerningAttribute
    public typealias Tracking = AttributeScopes.SwiftUIAttributes.TrackingAttribute
    public typealias BaselineOffset = AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute
}
