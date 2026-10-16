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

/// How a view with an aspect ratio fits the space it is offered. Apple: https://developer.apple.com/documentation/swiftui/contentmode
public enum ContentMode: Hashable, Sendable {
    case fit, fill
}

/// A resolved image reference. The backend loads the image; the runtime carries only the reference.
public enum ImageReference: Hashable, Sendable {
    /// An SF Symbol name, as `Image(systemName:)` takes it.
    case system(String)
    /// An asset name, as `Image(_:)` takes it.
    case named(String)
    /// Decoded pixels with the scale they are drawn at, as `Image(decorative:scale:)` takes them.
    case pixels(RGBAImage, scale: CGFloat)

    public var name: String {
        switch self {
        case .system(let name), .named(let name): return name
        case .pixels(let image, _): return "pixels:\(image.width)x\(image.height)"
        }
    }
}

extension ImageReference {
    /// The accessibility name of an image with no `.accessibilityLabel`: the SF Symbol's own description where one was measured on macOS 27
    /// (`star.fill` is "Favorite" on the Mac; a screen reader must not say "star.fill"), else the name the image was made with.
    public var accessibilityName: String {
        if case .system(let symbol) = self, let described = SFSymbolDescriptions.measured[symbol] { return described }
        return name
    }
}

/// SF Symbol descriptions measured on macOS 27 (the AX name of an unlabelled `Image(systemName:)`). Only measured symbols are listed; the rest
/// fall back to the symbol name, which is the gap this table grows from. Measured: AXDump of factory/pipeline/blocks-37-38/swiftui.uia-walk/controls-b-v1.
public enum SFSymbolDescriptions {
    public static let measured: [String: String] = ["star.fill": "Favorite"]
}

/// A decoded raster: straight-alpha (non-premultiplied) RGBA8, row-major, top row first, no row padding.
/// Equality and hashing use the content id (a 64-bit FNV-1a of the dimensions and bytes), so comparing two images never scans the pixels.
public struct RGBAImage: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
    /// Stable across processes and runs: equal pixels give an equal id.
    public let contentID: UInt64

    /// Nil when a dimension is not positive or `rgba.count != width * height * 4`.
    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, width <= 1 << 20, height <= 1 << 20, rgba.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ byte: UInt8) { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        for shift in stride(from: 0, to: 64, by: 8) { mix(UInt8(truncatingIfNeeded: UInt64(width) >> UInt64(shift))) }
        for shift in stride(from: 0, to: 64, by: 8) { mix(UInt8(truncatingIfNeeded: UInt64(height) >> UInt64(shift))) }
        rgba.withUnsafeBufferPointer { for byte in $0 { mix(byte) } }
        contentID = hash
    }

    public static func == (a: RGBAImage, b: RGBAImage) -> Bool { a.contentID == b.contentID && a.width == b.width && a.height == b.height }
    public func hash(into hasher: inout Hasher) { hasher.combine(contentID); hasher.combine(width); hasher.combine(height) }
}

/// Image resize details resolved for a host renderer.
public struct ResolvedImageSizing: Hashable, Sendable {
    public let isResizable: Bool
    public let capInsets: EdgeInsets
    public let resizingMode: Image.ResizingMode
    /// `scaledToFit()` / `aspectRatio(_:contentMode: .fit)`.
    public let scalesToFit: Bool
    /// `scaledToFill()` / `aspectRatio(_:contentMode: .fill)`.
    public let scalesToFill: Bool
    /// An explicit width / height from `aspectRatio(_:contentMode:)`; nil keeps the image's own aspect.
    public let aspectRatio: CGFloat?
    /// `.interpolation(_:)`; nil when never set (the Mac default draws like `.low`, measured in wave 1 block I2).
    public let interpolation: Image.Interpolation?
    /// `.antialiased(_:)`; nil when never set. The Mac draws image rectangles on whole device pixels, so it has no pixel effect (measured, block I2).
    public let antialiased: Bool?

    init(isResizable: Bool, capInsets: EdgeInsets, resizingMode: Image.ResizingMode, scalesToFit: Bool,
         scalesToFill: Bool = false, aspectRatio: CGFloat? = nil, interpolation: Image.Interpolation? = nil, antialiased: Bool? = nil) {
        self.isResizable = isResizable
        self.capInsets = capInsets
        self.resizingMode = resizingMode
        self.scalesToFit = scalesToFit
        self.scalesToFill = scalesToFill
        self.aspectRatio = aspectRatio
        self.interpolation = interpolation
        self.antialiased = antialiased
    }

    /// True when any I2 field is set, so a non-resizable image that asks for an interpolation still reaches the host.
    var isNonDefault: Bool { scalesToFill || aspectRatio != nil || interpolation != nil || antialiased != nil }
}

struct ImageSpec: Hashable, Sendable {
    let reference: ImageReference
    let sizing: ResolvedImageSizing
    /// Accessibility label given at construction (`Image(_ cgImage:scale:orientation:label:)`); nil = the reference name.
    var labelText: String? = nil
}

/// Apple: https://developer.apple.com/documentation/swiftui/image
/// Image accessibility label defaults to the symbol or asset name until `.accessibilityLabel(_:)` overrides it.
/// Apple's default label derivation is not documented per symbol, so this is a chosen default (see RESULT.md).
@MainActor
public struct Image: View, PrimitiveView {
    let reference: ImageReference
    /// Set by the CGImage-shaped initialisers (the `label:` text).
    var labelText: String?
    private var capInsets = EdgeInsets()
    private var resizingMode: ResizingMode = .stretch
    private var isResizable = false
    private var scalesToFit = false
    private var scalesToFill = false
    private var aspectRatioValue: CGFloat?
    private var interpolationValue: Interpolation?
    private var antialiasedValue: Bool?

    /// Apple: https://developer.apple.com/documentation/swiftui/image/interpolation
    public enum Interpolation: Hashable, Sendable {
        case none, low, medium, high
    }

    /// How a resizable image fills space beyond its cap insets.
    public enum ResizingMode: Hashable, Sendable {
        case stretch
        case tile
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(systemname:)
    public init(systemName: String) { reference = .system(systemName) }

    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(_:)
    public init(_ name: String) { reference = .named(name) }

    /// Draws decoded pixels. The intrinsic size is the pixel size divided by `scale` (points); the image is not resizable until `.resizable()`.
    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(decorative:scale:orientation:)
    /// `nonisolated`, as SwiftUI's: a value type that a nonisolated model (Pulse's `HubImage.image(fitting:)`) wraps in an Image.
    nonisolated public init(decorative image: RGBAImage, scale: CGFloat = 1) { reference = .pixels(image, scale: scale > 0 ? scale : 1) }

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
        image.scalesToFill = false
        return image
    }

    /// Fills the proposed bounds while preserving the aspect ratio; the overflow is not clipped unless `.clipped()` follows.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/scaledtofill()
    public func scaledToFill() -> Self {
        var image = self
        image.scalesToFill = true
        image.scalesToFit = false
        return image
    }

    /// `aspectRatio` is width / height; nil uses the image's own. Apple: https://developer.apple.com/documentation/swiftui/view/aspectratio(_:contentmode:)-771ow
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> Self {
        var image = self
        image.aspectRatioValue = aspectRatio.flatMap { $0 > 0 ? $0 : nil }
        image.scalesToFit = contentMode == .fit
        image.scalesToFill = contentMode == .fill
        return image
    }

    /// Chooses the resampling filter the host uses when the image is drawn at another size. Apple: https://developer.apple.com/documentation/swiftui/image/interpolation(_:)
    public func interpolation(_ interpolation: Interpolation) -> Self {
        var image = self
        image.interpolationValue = interpolation
        return image
    }

    /// Whether the image's edges are antialiased. Apple: https://developer.apple.com/documentation/swiftui/image/antialiased(_:)
    public func antialiased(_ isAntialiased: Bool) -> Self {
        var image = self
        image.antialiasedValue = isAntialiased
        return image
    }

    var sizing: ResolvedImageSizing {
        ResolvedImageSizing(
            isResizable: isResizable,
            capInsets: capInsets,
            resizingMode: resizingMode,
            scalesToFit: scalesToFit,
            scalesToFill: scalesToFill,
            aspectRatio: aspectRatioValue,
            interpolation: interpolationValue,
            antialiased: antialiasedValue
        )
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .image(ImageSpec(reference: reference, sizing: sizing, labelText: labelText)) }
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
    /// A semantic colour at a fixed opacity (`Color.primary.opacity(0.5)`), multiplied into the colour's own alpha by the host.
    case semanticAlpha(String, Double)

    /// This colour times `alpha` (clamped to 0...1).
    func multiplied(by alpha: Double) -> ResolvedColor {
        let a = min(max(alpha, 0), 1)
        switch self {
        case .rgba(let r, let g, let b, let o): return .rgba(r, g, b, o * a)
        case .semantic(let name): return .semanticAlpha(name, a)
        case .semanticAlpha(let name, let o): return .semanticAlpha(name, o * a)
        }
    }
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

    /// A grey (`red == green == blue == white`), sRGB. Apple: https://developer.apple.com/documentation/swiftui/color/init(white:opacity:)
    public init(white: Double, opacity: Double = 1) {
        resolvedColor = .rgba(white, white, white, opacity)
    }

    init(semantic name: String) {
        resolvedColor = .semantic(name)
    }
}

extension Color {
    init(resolved: ResolvedColor) { resolvedColor = resolved }

    /// A fully transparent colour. Apple: https://developer.apple.com/documentation/swiftui/color/clear
    public static var clear: Color { Color(semantic: "clear") }

    /// This colour at `opacity` times its own. Returns a `Color`, not a view, so it is usable as a fill (`.fill(Color.black.opacity(0.1))`); the `View.opacity`
    /// modifier stays for every other view.
    /// Apple: https://developer.apple.com/documentation/swiftui/color/opacity(_:)
    public func opacity(_ opacity: Double) -> Color { Color(resolved: resolvedColor.multiplied(by: opacity)) }
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
    public static var clear: Color { Color(semantic: "clear") }
}

/// A font, as SwiftUI names it. `id` is the resolved identifier used by text measurement.
/// Apple: https://developer.apple.com/documentation/swiftui/font
public struct Font: Hashable, Sendable {
    public let id: String
    /// Explicit family and style facts used by text measurement. Legacy font values leave this unset.
    private let metadataStorage: MetadataStorage?

    public var metadata: Metadata? { metadataStorage?.value }

    /// Immutable indirect storage keeps optional font metadata off every legacy Font value.
    private final class MetadataStorage: Hashable, Sendable {
        let value: Metadata

        init(_ value: Metadata) {
            self.value = value
        }

        static func == (lhs: MetadataStorage, rhs: MetadataStorage) -> Bool {
            lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            value.hash(into: &hasher)
        }
    }

    public struct Metadata: Hashable, Sendable {
        public let familyName: String?
        public let pointSize: CGFloat?
        public let weight: Weight?
        public let design: Design?
        public let isCustom: Bool
        /// The text style a style font (`.title`, `.headline`, ...) was made from, by name ("largeTitle", "title", "title2", "title3", "headline", "subheadline",
        /// "body", "callout", "footnote", "caption", "caption2"); nil for a sized system font or a custom one.
        public let textStyle: String?
        /// `Font.width(_:)`, nil unless one was set.
        public let width: Width?
        /// `Font.bold()` on a text style: the style's emphasized weight (macOS: title3, body, callout, ... semibold; headline heavy; caption medium), not `.bold`. False when a
        /// weight was set after it.
        public let isEmphasized: Bool
        /// `Font.monospacedDigit()`: tabular figures (the OpenType `tnum` feature on Windows).
        public let monospacedDigit: Bool

        public init(familyName: String? = nil, pointSize: CGFloat? = nil, weight: Weight? = nil,
                    design: Design? = nil, isCustom: Bool = false, textStyle: String? = nil, width: Width? = nil,
                    isEmphasized: Bool = false, monospacedDigit: Bool = false) {
            self.isEmphasized = isEmphasized
            self.monospacedDigit = monospacedDigit
            self.familyName = familyName
            self.pointSize = pointSize
            self.weight = weight
            self.design = design
            self.isCustom = isCustom
            self.textStyle = textStyle
            self.width = width
        }
    }

    init(id: String) {
        self.id = id
        metadataStorage = nil
    }

    private init(id: String, metadata: Metadata) {
        self.id = id
        metadataStorage = MetadataStorage(metadata)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/weight (the nine weights, light to heavy).
    public enum Weight: String, Hashable, Sendable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black

        /// The CSS / OpenType weight class (100 to 900) a renderer selects a face by.
        public var classValue: UInt32 {
            switch self {
            case .ultraLight: return 100
            case .thin: return 200
            case .light: return 300
            case .regular: return 400
            case .medium: return 500
            case .semibold: return 600
            case .bold: return 700
            case .heavy: return 800
            case .black: return 900
            }
        }
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/width. Carried with the font; a face without a width axis (Segoe UI) draws every width alike.
    public struct Width: Hashable, Sendable {
        public let name: String
        private init(_ name: String) { self.name = name }
        public static let compressed = Width("compressed")
        public static let condensed = Width("condensed")
        public static let standard = Width("standard")
        public static let expanded = Width("expanded")
    }

    public enum Design: String, Hashable, Sendable {
        case `default`
        case serif
        case rounded
        case monospaced
    }

    public static let largeTitle = Font(id: "textStyle.largeTitle", metadata: Metadata(textStyle: "largeTitle"))
    public static let title = Font(id: "textStyle.title", metadata: Metadata(textStyle: "title"))
    public static let title2 = Font(id: "textStyle.title2", metadata: Metadata(textStyle: "title2"))
    public static let title3 = Font(id: "textStyle.title3", metadata: Metadata(textStyle: "title3"))
    public static let headline = Font(id: "textStyle.headline", metadata: Metadata(textStyle: "headline"))
    public static let subheadline = Font(id: "textStyle.subheadline", metadata: Metadata(textStyle: "subheadline"))
    public static let body = Font(id: "textStyle.body", metadata: Metadata(textStyle: "body"))
    public static let callout = Font(id: "textStyle.callout", metadata: Metadata(textStyle: "callout"))
    public static let footnote = Font(id: "textStyle.footnote", metadata: Metadata(textStyle: "footnote"))
    public static let caption = Font(id: "textStyle.caption", metadata: Metadata(textStyle: "caption"))
    public static let caption2 = Font(id: "textStyle.caption2", metadata: Metadata(textStyle: "caption2"))

    public static func system(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(id: "system(\(size),\(weight.rawValue))", metadata: Metadata(pointSize: size, weight: weight))
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
            Metadata(familyName: $0.familyName, pointSize: $0.pointSize, weight: weight, design: $0.design, isCustom: $0.isCustom,
                     textStyle: $0.textStyle, width: $0.width, isEmphasized: false, monospacedDigit: $0.monospacedDigit)
        }
        if let metadata { return Font(id: "\(id)|weight(\(weight.rawValue))", metadata: metadata) }
        return Font(id: "\(id)|weight(\(weight.rawValue))")
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/width(_:)
    public func width(_ width: Width) -> Font {
        let base = metadata ?? Metadata()
        return Font(id: "\(id)|width(\(width.name))",
                    metadata: Metadata(familyName: base.familyName, pointSize: base.pointSize, weight: base.weight, design: base.design, isCustom: base.isCustom,
                                       textStyle: base.textStyle, width: width, isEmphasized: base.isEmphasized, monospacedDigit: base.monospacedDigit))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/bold(). On a text style this is the style's emphasized weight (measured on macOS 27, decision G25), on a
    /// sized system or custom font it is `.bold`.
    public func bold() -> Font {
        let base = metadata ?? Metadata()
        if base.textStyle != nil && !base.isCustom {
            return Font(id: "\(id)|bold()", metadata: Metadata(familyName: base.familyName, pointSize: base.pointSize, weight: nil, design: base.design, isCustom: false,
                                                               textStyle: base.textStyle, width: base.width, isEmphasized: true, monospacedDigit: base.monospacedDigit))
        }
        return weight(.bold)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/font/monospaceddigit(). Tabular figures.
    public func monospacedDigit() -> Font {
        let base = metadata ?? Metadata()
        return Font(id: "\(id)|monospacedDigit", metadata: Metadata(familyName: base.familyName, pointSize: base.pointSize, weight: base.weight, design: base.design,
                                                                  isCustom: base.isCustom, textStyle: base.textStyle, width: base.width,
                                                                  isEmphasized: base.isEmphasized, monospacedDigit: true))
    }
}

// MARK: - Environment keys for style and enablement

private enum EnabledKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

private enum FontKey: EnvironmentKey {
    static var defaultValue: Font? { nil }
}

private enum LineLimitKey: EnvironmentKey {
    static var defaultValue: Int? { nil }
}

private enum TextCaseKey: EnvironmentKey {
    static var defaultValue: Text.Case? { nil }
}

private enum DefaultScrollAnchorKey: EnvironmentKey {
    static var defaultValue: UnitPoint? { nil }
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

    /// Maximum visible line count for descendant Text views; nil leaves text unbounded.
    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }

    /// `.textCase(_:)`: the case descendant Text views display in; nil leaves the text as written.
    public var textCase: Text.Case? {
        get { self[TextCaseKey.self] }
        set { self[TextCaseKey.self] = newValue }
    }

    /// Where a scroll view first positions its content (`.defaultScrollAnchor`); nil starts at the leading/top edge.
    var defaultScrollAnchor: UnitPoint? {
        get { self[DefaultScrollAnchorKey.self] }
        set { self[DefaultScrollAnchorKey.self] = newValue }
    }

    public var foregroundStyle: ResolvedColor? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }
}
