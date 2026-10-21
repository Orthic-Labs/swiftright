import Foundation

// Issue #68 (MarkdownUI on SwiftRight): LabelStyle and `AnyShapeStyle`.
//
// `Label` stays the runtime's primitive (icon, then title, 6 pt apart, centred). With no `.labelStyle`, or with `.automatic` / `.titleAndIcon`, it lays out exactly as before.
// With `.titleOnly`, `.iconOnly` or a custom `LabelStyle`, the Label node's content becomes the style's `makeBody(configuration:)` result (the node stays a "Label").

/// Apple: https://developer.apple.com/documentation/swiftui/labelstyle
@MainActor @preconcurrency
public protocol LabelStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor func makeBody(configuration: Configuration) -> Body
    typealias Configuration = LabelStyleConfiguration
}

/// The title and icon of the `Label` a style is making the body of.
/// Apple: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration
public struct LabelStyleConfiguration {
    /// The label's title view. Apple: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/title-swift.struct
    public struct Title: View, ViewContainer {
        nonisolated(unsafe) let content: any View
        nonisolated init(_ content: any View) { self.content = content }
        @MainActor public var body: Never { return fatalError("Title has no body") }
        @MainActor func parts() -> [(Segment, any View)] { [(.erased, content)] }
    }

    /// The label's icon view. Apple: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/icon-swift.struct
    public struct Icon: View, ViewContainer {
        nonisolated(unsafe) let content: any View
        nonisolated init(_ content: any View) { self.content = content }
        @MainActor public var body: Never { return fatalError("Icon has no body") }
        @MainActor func parts() -> [(Segment, any View)] { [(.erased, content)] }
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/title-swift.property
    public var title: Title
    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/icon-swift.property
    public var icon: Icon

    init(title: any View, icon: any View) {
        self.title = Title(title)
        self.icon = Icon(icon)
    }
}

/// The platform's default Label look: icon and title. Apple: https://developer.apple.com/documentation/swiftui/defaultlabelstyle
public struct DefaultLabelStyle: LabelStyle {
    public init() {}
    @MainActor public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {   // measured on macOS 27 (Label.iconTitleSpacing)
            configuration.icon
            configuration.title
        }
    }
}

/// Icon and title. Apple: https://developer.apple.com/documentation/swiftui/titleandiconlabelstyle
public struct TitleAndIconLabelStyle: LabelStyle {
    public init() {}
    @MainActor public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {   // measured on macOS 27 (Label.iconTitleSpacing)
            configuration.icon
            configuration.title
        }
    }
}

/// Only the title. Apple: https://developer.apple.com/documentation/swiftui/titleonlylabelstyle
public struct TitleOnlyLabelStyle: LabelStyle {
    public init() {}
    @MainActor public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

/// Only the icon. Apple: https://developer.apple.com/documentation/swiftui/icononlylabelstyle
public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    @MainActor public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyle/automatic
    public static var automatic: DefaultLabelStyle { DefaultLabelStyle() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyle/titleandicon
    public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyle/titleonly
    public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
    /// Apple: https://developer.apple.com/documentation/swiftui/labelstyle/icononly
    public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() }
}

/// The `.labelStyle` in effect, type-erased. `isDefaultLook` styles leave the Label's own layout alone.
struct LabelStyleBox {
    let isDefaultLook: Bool
    let make: @MainActor (LabelStyleConfiguration) -> any View

    @MainActor init<S: LabelStyle>(_ style: S) {
        isDefaultLook = S.self == DefaultLabelStyle.self || S.self == TitleAndIconLabelStyle.self
        make = { configuration in AnyView(style.makeBody(configuration: configuration)) }
    }
}

private enum LabelStyleKey: EnvironmentKey {
    static var defaultValue: LabelStyleBox? { nil }
}

extension EnvironmentValues {
    var labelStyleBox: LabelStyleBox? {
        get { self[LabelStyleKey.self] }
        set { self[LabelStyleKey.self] = newValue }
    }
}

extension View {
    /// Applies `style` to the Labels in this view (the nearest `labelStyle` wins).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/labelstyle(_:)
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        let box = LabelStyleBox(style)
        return Modified(content: self, spec: .environment({ (environment: inout EnvironmentValues) in
            environment.labelStyleBox = box
        }))
    }
}

/// The parts of a `Label`, as the graph reads them to build a styled body.
@MainActor
protocol LabelParts {
    var titleView: any View { get }
    var iconView: any View { get }
}

extension Label: LabelParts {
    var titleView: any View { title }
    var iconView: any View { icon }
}

@MainActor
extension Graph {
    /// The content of a Label node under a style that changes its look; nil under no style or a default-look one (the Label then expands to its own icon-and-title stack).
    func styledLabelContent(_ node: Node) -> (any View)? {
        guard let box = node.environment.labelStyleBox, !box.isDefaultLook, let label = node.view as? any LabelParts else { return nil }
        return box.make(LabelStyleConfiguration(title: label.titleView, icon: label.iconView))
    }
}

/// A shape style of any kind, type-erased. Resolves to the wrapped style's colour.
/// Apple: https://developer.apple.com/documentation/swiftui/anyshapestyle
public struct AnyShapeStyle: ShapeStyle {
    public let resolvedColor: ResolvedColor

    /// Apple: https://developer.apple.com/documentation/swiftui/anyshapestyle/init(_:)
    public init<S: ShapeStyle>(_ style: S) {
        resolvedColor = style.resolvedColor
    }
}
