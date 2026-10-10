import Foundation

// Toggle, Image, TextEditor, Label, Divider, and the style values (Color, Font). Each keeps the SwiftUI
// signature and a model node kind. The backend draws them; the runtime resolves them into the commit record.

// MARK: - Visibility

/// Title visibility of a confirmation dialog.
/// Apple: https://developer.apple.com/documentation/swiftui/visibility
public enum Visibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
}

// MARK: - Toggle

/// A switch bound to a Boolean. The accessibility role is "checkbox" and the value is "1" (on) or "0" (off).
/// Apple: https://developer.apple.com/documentation/swiftui/toggle
@MainActor
public struct Toggle<Label: View>: View, PrimitiveView {
    let isOn: Binding<Bool>
    let label: Label

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .toggle(isOn) }
    var nodeContent: (any View)? { label }
}

extension Toggle where Label == Text {
    /// Apple: https://developer.apple.com/documentation/swiftui/toggle/init(_:ison:)
    public init(_ titleKey: String, isOn: Binding<Bool>) {
        let label: () -> Text = { Text(titleKey) }
        self.init(isOn: isOn, label: label)
    }
}

extension Toggle: @MainActor LabeledControl {
    var titleView: any View { label }
}

// MARK: - Image

/// A resolved image reference. The backend loads the image; the runtime carries only the reference.
public enum ImageReference: Hashable, Sendable {
    /// An SF Symbol name, as `Image(systemName:)` takes it.
    case system(String)
    /// An asset name, as `Image(_:)` takes it.
    case named(String)

    public var name: String {
        switch self {
        case .system(let name), .named(let name): return name
        }
    }
}

/// Image resize details resolved for a host renderer.
public struct ResolvedImageSizing: Hashable, Sendable {
    public let isResizable: Bool
    public let capInsets: EdgeInsets
    public let resizingMode: Image.ResizingMode
    public let scalesToFit: Bool

    init(isResizable: Bool, capInsets: EdgeInsets, resizingMode: Image.ResizingMode, scalesToFit: Bool) {
        self.isResizable = isResizable
        self.capInsets = capInsets
        self.resizingMode = resizingMode
        self.scalesToFit = scalesToFit
    }
}

struct ImageSpec: Hashable, Sendable {
    let reference: ImageReference
    let sizing: ResolvedImageSizing
}

/// Apple: https://developer.apple.com/documentation/swiftui/image
/// Image accessibility label defaults to the symbol or asset name until `.accessibilityLabel(_:)` overrides it.
/// Apple's default label derivation is not documented per symbol, so this is a chosen default (see RESULT.md).
@MainActor
public struct Image: View, PrimitiveView {
    let reference: ImageReference
    private var capInsets = EdgeInsets()
    private var resizingMode: ResizingMode = .stretch
    private var isResizable = false
    private var scalesToFit = false

    /// How a resizable image fills space beyond its cap insets.
    public enum ResizingMode: Hashable, Sendable {
        case stretch
        case tile
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(systemname:)
    public init(systemName: String) { reference = .system(systemName) }

    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(_:)
    public init(_ name: String) { reference = .named(name) }

    /// Lets image content resize to proposed dimensions.
    /// Apple: https://developer.apple.com/documentation/swiftui/image/resizable(capInsets:resizingMode:)
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Self {
        var image = self
        image.capInsets = capInsets
        image.resizingMode = resizingMode
        image.isResizable = true
        return image
    }

    /// Fits a resizable image inside its proposed bounds while preserving its aspect ratio.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/scaledtofit()
    public func scaledToFit() -> Self {
        var image = self
        image.scalesToFit = true
        return image
    }

    var sizing: ResolvedImageSizing {
        ResolvedImageSizing(
            isResizable: isResizable,
            capInsets: capInsets,
            resizingMode: resizingMode,
            scalesToFit: scalesToFit
        )
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .image(ImageSpec(reference: reference, sizing: sizing)) }
    var nodeContent: (any View)? { nil }
}

// MARK: - TextEditor

/// Multi-line editable text. It shares the TextInputState model with TextField (composition, selection, marked
/// text). Return inserts a line break. It takes the proposed size on each axis when finite.
/// Apple: https://developer.apple.com/documentation/swiftui/texteditor
@MainActor
public struct TextEditor: View, PrimitiveView {
    let text: Binding<String>

    public init(text: Binding<String>) { self.text = text }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .textEditor(text) }
    var nodeContent: (any View)? { nil }
}

// MARK: - Label

/// Icon and title side by side. The commit record shows the node as "Label" with icon then title.
/// Apple: https://developer.apple.com/documentation/swiftui/label
@MainActor
public struct Label<Title: View, Icon: View>: View, PrimitiveView {
    let title: Title
    let icon: Icon

    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "Label", axis: .horizontal, cross: .middle, spacing: 6, fillsCross: false))
    }
    var nodeContent: (any View)? { TupleView((icon, title)) }
}

extension Label where Title == Text, Icon == Image {
    /// Apple: https://developer.apple.com/documentation/swiftui/label/init(_:systemimage:)
    public init(_ titleKey: String, systemImage name: String) {
        let title: () -> Text = { Text(titleKey) }
        let icon: () -> Image = { Image(systemName: name) }
        self.init(title: title, icon: icon)
    }
}

// MARK: - Divider

/// A thin separator: horizontal in a VStack, vertical in an HStack. Thickness is 1 logical point.
/// Apple: https://developer.apple.com/documentation/swiftui/divider
@MainActor
public struct Divider: View, PrimitiveView {
    public init() {}

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .divider }
    var nodeContent: (any View)? { nil }
}

/// Thickness of a Divider, in logical points.
let dividerThickness: CGFloat = 1

// MARK: - Style values

/// A resolved colour. Semantic names are resolved by the backend to its system colour set.
public enum ResolvedColor: Hashable, Sendable {
    case semantic(String)
    case rgba(Double, Double, Double, Double)
}

/// Apple: https://developer.apple.com/documentation/swiftui/shapestyle
public protocol ShapeStyle: Sendable {
    var resolvedColor: ResolvedColor { get }
}

/// Apple: https://developer.apple.com/documentation/swiftui/color
public struct Color: ShapeStyle, Hashable, Sendable {
    public let resolvedColor: ResolvedColor

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        resolvedColor = .rgba(red, green, blue, opacity)
    }

    init(semantic name: String) {
        resolvedColor = .semantic(name)
    }
}

extension Color: View, PrimitiveView {
    @MainActor public var body: Never { return fatalError("Color has no body") }
    var nodeKind: NodeKind { .color(resolvedColor) }
    var nodeContent: (any View)? { nil }
}

/// Static members are reached as `Color.red` and so on, as in SwiftUI. Names are semantic, not RGB.
extension ShapeStyle where Self == Color {
    public static var primary: Color { Color(semantic: "label") }
    public static var secondary: Color { Color(semantic: "secondaryLabel") }
    public static var red: Color { Color(semantic: "system.red") }
    public static var orange: Color { Color(semantic: "system.orange") }
    public static var yellow: Color { Color(semantic: "system.yellow") }
    public static var green: Color { Color(semantic: "system.green") }
    public static var blue: Color { Color(semantic: "system.blue") }
    public static var purple: Color { Color(semantic: "system.purple") }
    public static var pink: Color { Color(semantic: "system.pink") }
    public static var gray: Color { Color(semantic: "system.gray") }
    public static var black: Color { Color(semantic: "black") }
    public static var white: Color { Color(semantic: "white") }
}

/// A font, as SwiftUI names it. `id` is the resolved identifier used by text measurement.
/// Apple: https://developer.apple.com/documentation/swiftui/font
public struct Font: Hashable, Sendable {
    public let id: String
    /// Explicit family and style facts used by text measurement. Legacy font values leave this unset.
    public let metadata: Metadata?

    public struct Metadata: Hashable, Sendable {
        public let familyName: String?
        public let pointSize: CGFloat?
        public let weight: Weight?
        public let design: Design?
        public let isCustom: Bool

        public init(familyName: String? = nil, pointSize: CGFloat? = nil, weight: Weight? = nil,
                    design: Design? = nil, isCustom: Bool = false) {
            self.familyName = familyName
            self.pointSize = pointSize
            self.weight = weight
            self.design = design
            self.isCustom = isCustom
        }
    }

    init(id: String) {
        self.id = id
        metadata = nil
    }

    private init(id: String, metadata: Metadata) {
        self.id = id
        self.metadata = metadata
    }

    public enum Weight: String, Hashable, Sendable {
        case regular
        case medium
        case semibold
        case bold
    }

    public enum Design: String, Hashable, Sendable {
        case `default`
        case serif
        case rounded
        case monospaced
    }

    public static let largeTitle = Font(id: "textStyle.largeTitle")
    public static let title = Font(id: "textStyle.title")
    public static let title2 = Font(id: "textStyle.title2")
    public static let title3 = Font(id: "textStyle.title3")
    public static let headline = Font(id: "textStyle.headline")
    public static let subheadline = Font(id: "textStyle.subheadline")
    public static let body = Font(id: "textStyle.body")
    public static let callout = Font(id: "textStyle.callout")
    public static let footnote = Font(id: "textStyle.footnote")
    public static let caption = Font(id: "textStyle.caption")
    public static let caption2 = Font(id: "textStyle.caption2")

    public static func system(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(id: "system(\(size),\(weight.rawValue))")
    }

    /// Creates a system font with an explicit design descriptor for measurement backends.
    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design) -> Font {
        Font(
            id: "system(\(size),\(weight.rawValue))",
            metadata: Metadata(pointSize: size, weight: weight, design: design)
        )
    }

    /// Creates a font for a named family. Family metadata is passed to measurers without claiming a rendered glyph identity.
    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(
            id: "custom(\(name),\(size))",
            metadata: Metadata(familyName: name, pointSize: size, isCustom: true)
        )
    }

    public func weight(_ weight: Font.Weight) -> Font {
        let metadata = self.metadata.map {
            Metadata(familyName: $0.familyName, pointSize: $0.pointSize, weight: weight, design: $0.design, isCustom: $0.isCustom)
        }
        if let metadata { return Font(id: "\(id)|weight(\(weight.rawValue))", metadata: metadata) }
        return Font(id: "\(id)|weight(\(weight.rawValue))")
    }
}

// MARK: - Environment keys for style and enablement

private enum EnabledKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

private enum FontKey: EnvironmentKey {
    static var defaultValue: Font? { nil }
}

private enum ForegroundStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedColor? { nil }
}

extension EnvironmentValues {
    /// False inside `.disabled(true)`. Controls read it at dispatch time.
    public var isEnabled: Bool {
        get { self[EnabledKey.self] }
        set { self[EnabledKey.self] = newValue }
    }

    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }

    public var foregroundStyle: ResolvedColor? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }
}
