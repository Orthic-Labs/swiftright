import Foundation

// Issue #60 (SR1 backlog), first pass: Form and Section (and `.formStyle`, accepted and not drawn).
//
// Section is a TRANSPARENT container, like Group: its header, content and footer are spliced into the parent as direct children, so a Section inside a List keeps its rows
// as List rows (selection, keyboard navigation and `onDelete` see them) and a Section inside a Form or VStack lays out as its parts in order. The header is drawn in `.headline`
// and the footer in `.caption` in the secondary colour. SwiftUI draws both differently by container (a sidebar List's header is small grey caps, a grouped Form's is a
// bold line above a rounded group); this first pass uses one style everywhere.
//
// Form is a vertical ScrollView over a leading-aligned VStack with 10 pt between its children and 20 pt around them. SwiftUI's macOS Form (the grouped style) puts each
// Section in a rounded group and aligns labels in a column; neither is drawn. Metrics are guesses, not measured on macOS 27.

enum FormMetrics {
    static let padding: CGFloat = 20
    static let rowSpacing: CGFloat = 10
}

/// Apple: https://developer.apple.com/documentation/swiftui/section
public struct Section<Parent: View, Content: View, Footer: View>: View, ViewContainer {
    let header: Parent
    let content: Content
    let footer: Footer

    init(header: Parent, content: Content, footer: Footer) {
        self.header = header
        self.content = content
        self.footer = footer
    }

    @MainActor public var body: Never { return fatalError("Section has no body") }

    @MainActor func parts() -> [(Segment, any View)] {
        var out: [(Segment, any View)] = []
        if Parent.self != EmptyView.self { out.append((.index(0), header.font(.headline))) }
        out.append((.index(1), content))
        if Footer.self != EmptyView.self { out.append((.index(2), footer.font(.caption).foregroundStyle(Color.secondary))) }
        return out
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(content:)
    public init(@ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: EmptyView())
    }
}

extension Section where Footer == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(header:content:)
    public init(header: Parent, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content(), footer: EmptyView())
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(content:header:)
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(header: header(), content: content(), footer: EmptyView())
    }
}

extension Section where Parent == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(footer:content:)
    public init(footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: footer)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(content:footer:)
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(header: EmptyView(), content: content(), footer: footer())
    }
}

extension Section {
    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(header:footer:content:)
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content(), footer: footer)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/section/init(content:header:footer:)
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
        self.init(header: header(), content: content(), footer: footer())
    }
}

extension Section where Parent == Text, Footer == EmptyView {
    /// A section titled with a string. Apple: https://developer.apple.com/documentation/swiftui/section/init(_:content:)
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(header: Text(title), content: content(), footer: EmptyView())
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/form
public struct Form<Content: View>: View {
    let content: Content

    /// Apple: https://developer.apple.com/documentation/swiftui/form/init(content:)
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @MainActor public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormMetrics.rowSpacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FormMetrics.padding)
        }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/formstyle
public protocol FormStyle: Sendable {}

/// Apple: https://developer.apple.com/documentation/swiftui/automaticformstyle
public struct AutomaticFormStyle: FormStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/columnsformstyle
public struct ColumnsFormStyle: FormStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/groupedformstyle
public struct GroupedFormStyle: FormStyle { public init() {} }

extension FormStyle where Self == AutomaticFormStyle {
    public static var automatic: AutomaticFormStyle { AutomaticFormStyle() }
}
extension FormStyle where Self == ColumnsFormStyle {
    public static var columns: ColumnsFormStyle { ColumnsFormStyle() }
}
extension FormStyle where Self == GroupedFormStyle {
    public static var grouped: GroupedFormStyle { GroupedFormStyle() }
}

extension View {
    /// Accepted so SwiftUI code compiles; the style is not drawn (see the file header: one Form look).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/formstyle(_:)
    public func formStyle<S: FormStyle>(_ style: S) -> some View {
        self
    }
}
