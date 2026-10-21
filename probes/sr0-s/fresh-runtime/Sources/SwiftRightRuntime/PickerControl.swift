import Foundation

// Issue #60 (SR1 backlog), first pass: Picker (menu style by default, as on macOS; segmented, inline and radio-group styles) and `.pickerStyle`.
//
// The options are read from the Picker's content: every view carrying `.tag(_:)` is an option (its label is the tagged view, its value the tag). A ForEach row without a
// tag uses its id as the tag, as SwiftUI does. An untagged view outside a ForEach is not selectable and is dropped. Only the tag and the label survive: other modifiers on an
// option's label (`.foregroundStyle`, `.font`) are dropped.
//
// MENU STYLE (the default): the label (unless `.labelsHidden()`), then a popup button: the selected option's text and a chevron pair, on a 12% grey rounded rectangle 22 pt
// tall with 8 pt side padding. The button is a `Menu` whose items are Buttons that write the selection, so the host's menu model presents them. The selected option is NOT
// marked with a check mark in the menu (a menu entry has no checked state in this runtime). Options that are not text-only show their plain text in the menu.
// SEGMENTED: one cell per option on a grey rounded track, the selected cell filled with the accent colour and its text white; cells size to their labels (macOS sizes
// them equally; not measured here). INLINE and RADIO GROUP: a column of options, each with a circle (filled when selected) before its label; tapping an option selects it.
// Every metric is a guess, not measured on macOS 27. The popup button chrome, the segment fill and the radio circles are drawn from shapes and system images;
// a host drawing the native control would replace them.

enum PickerStyleKind: Hashable, Sendable {
    case menu, segmented, inline, radioGroup
}

private enum PickerStyleKindKey: EnvironmentKey {
    static var defaultValue: PickerStyleKind { .menu }
}

extension EnvironmentValues {
    var pickerStyleKind: PickerStyleKind {
        get { self[PickerStyleKindKey.self] }
        set { self[PickerStyleKindKey.self] = newValue }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/pickerstyle
public protocol PickerStyle: Sendable {}

/// Apple: https://developer.apple.com/documentation/swiftui/defaultpickerstyle
public struct DefaultPickerStyle: PickerStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/menupickerstyle
public struct MenuPickerStyle: PickerStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/segmentedpickerstyle
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/inlinepickerstyle
public struct InlinePickerStyle: PickerStyle { public init() {} }
/// Apple: https://developer.apple.com/documentation/swiftui/radiogrouppickerstyle
public struct RadioGroupPickerStyle: PickerStyle { public init() {} }

extension PickerStyle where Self == DefaultPickerStyle {
    public static var automatic: DefaultPickerStyle { DefaultPickerStyle() }
}
extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}
extension PickerStyle where Self == SegmentedPickerStyle {
    public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
}
extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}
extension PickerStyle where Self == RadioGroupPickerStyle {
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}

extension View {
    /// Sets how the Pickers below draw (the default is the menu style). Apple: https://developer.apple.com/documentation/swiftui/view/pickerstyle(_:)
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        let kind: PickerStyleKind
        if style is SegmentedPickerStyle { kind = .segmented }
        else if style is InlinePickerStyle { kind = .inline }
        else if style is RadioGroupPickerStyle { kind = .radioGroup }
        else { kind = .menu }
        return environment(\.pickerStyleKind, kind)
    }
}

/// One selectable option of a Picker.
struct PickerOption {
    let index: Int
    let tag: AnyHashable
    let label: any View
    let text: String
}

/// The tagged views of a Picker's content, in order.
@MainActor
func pickerOptions(_ content: any View) -> [PickerOption] {
    var found: [(tag: AnyHashable, label: any View)] = []
    collectPickerOptions(content, fallback: nil, into: &found)
    return found.enumerated().map { PickerOption(index: $0.offset, tag: $0.element.tag, label: $0.element.label, text: ViewWalk.plainText($0.element.label)) }
}

@MainActor
private func collectPickerOptions(_ view: any View, fallback: AnyHashable?, into found: inout [(tag: AnyHashable, label: any View)]) {
    if view is EmptyView { return }
    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        if let child = mirror.children.first?.value as? any View { collectPickerOptions(child, fallback: fallback, into: &found) }
        return
    }
    if let wrapped = view as? WrappedModifier {
        if case .tag(let tag) = wrapped.modifierSpec {
            found.append((tag, wrapped.modifierInner))
        } else {
            collectPickerOptions(wrapped.modifierInner, fallback: fallback, into: &found)
        }
        return
    }
    if let container = view as? ViewContainer {
        for part in container.parts() {
            var inherited = fallback
            if case .keyed(let id) = part.0 { inherited = id }
            collectPickerOptions(part.1, fallback: inherited, into: &found)
        }
        return
    }
    if let fallback, view is PrimitiveView {
        found.append((fallback, view))
        return
    }
    if view is PrimitiveView { return }
    // A custom view: an option with the ForEach id when there is one, else whatever its body tags.
    if let fallback, !(view.evaluateBody() is WrappedModifier) {
        found.append((fallback, view))
    } else {
        collectPickerOptions(view.evaluateBody(), fallback: fallback, into: &found)
    }
}

enum PickerMetrics {
    static let popupHeight: CGFloat = 22
    static let popupSidePadding: CGFloat = 8
    static let cornerRadius: CGFloat = 5
    static let segmentHeight: CGFloat = 22
    static let segmentSidePadding: CGFloat = 10
}

/// Apple: https://developer.apple.com/documentation/swiftui/picker
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    let label: Label
    let selection: Binding<SelectionValue>
    let content: Content
    @Environment(\.pickerStyleKind) private var style
    @Environment(\.labelsHidden) private var labelsHidden

    /// Apple: https://developer.apple.com/documentation/swiftui/picker/init(selection:content:label:)
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.selection = selection
        self.content = content()
        self.label = label()
    }

    @MainActor public var body: some View {
        PickerBody(label: label, showsLabel: !labelsHidden, selection: selection, options: pickerOptions(content), style: style)
    }
}

extension Picker where Label == Text {
    /// Apple: https://developer.apple.com/documentation/swiftui/picker/init(_:selection:content:)
    public init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content, label: { Text(title) })
    }
}

/// The drawn Picker: label and control by style.
struct PickerBody<Label: View, SelectionValue: Hashable>: View {
    let label: Label
    let showsLabel: Bool
    let selection: Binding<SelectionValue>
    let options: [PickerOption]
    let style: PickerStyleKind

    @MainActor private func isSelected(_ option: PickerOption) -> Bool {
        option.tag == AnyHashable(selection.wrappedValue)
    }

    @MainActor private func select(_ option: PickerOption) {
        if let value = option.tag.base as? SelectionValue { selection.wrappedValue = value }
    }

    @MainActor private var selectedText: String {
        options.first { isSelected($0) }?.text ?? ""
    }

    @MainActor var body: some View {
        switch style {
        case .menu:
            HStack(spacing: 8) {
                if showsLabel { label }
                Menu(content: {
                    ForEach(options, id: \.index) { option in
                        Button(option.text) { select(option) }
                    }
                }, label: {
                    PickerPopupLabel(text: selectedText)
                })
            }
        case .segmented:
            HStack(spacing: 8) {
                if showsLabel { label }
                HStack(spacing: 0) {
                    ForEach(options, id: \.index) { option in
                        PickerSegment(label: AnyView(option.label), selected: isSelected(option))
                            .onTapGesture { select(option) }
                    }
                }
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: PickerMetrics.cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: PickerMetrics.cornerRadius))
            }
        case .inline, .radioGroup:
            VStack(alignment: .leading, spacing: 4) {
                if showsLabel { label }
                ForEach(options, id: \.index) { option in
                    HStack(spacing: 6) {
                        Image(systemName: isSelected(option) ? "largecircle.fill.circle" : "circle")
                        AnyView(option.label)
                    }
                    .onTapGesture { select(option) }
                }
            }
        }
    }
}

/// The popup button's face: the selected text and the chevron pair.
struct PickerPopupLabel: View {
    let text: String

    @MainActor var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.up.chevron.down")
        }
        .padding(.horizontal, PickerMetrics.popupSidePadding)
        .frame(height: PickerMetrics.popupHeight)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: PickerMetrics.cornerRadius))
    }
}

/// One cell of a segmented picker.
struct PickerSegment: View {
    let label: AnyView
    let selected: Bool

    @MainActor var body: some View {
        label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, PickerMetrics.segmentSidePadding)
            .frame(height: PickerMetrics.segmentHeight)
            .background(selected ? Color.accentColor : Color.clear)
    }
}
