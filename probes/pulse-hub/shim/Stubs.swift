// Probe-only, compile-only stubs: every declaration here is a gap in the SwiftRight runtime that Pulse's sources hit.
// They exist so the compiler can get past a gap and report the NEXT one; they do not draw or behave. Each block is tagged
// `GAP:<id>` and mirrors the real SwiftUI signature as far as Pulse uses it. Nothing here is product code.
import SwiftRightRuntime
import Foundation

// GAP:accessibility-modifiers (accessibilityElement/Value/Hint/AddTraits/Hidden; runtime only has accessibilityLabel(String))
public enum AccessibilityChildBehavior: Sendable { case ignore, combine, contain }
public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1)
    public static let isHeader = AccessibilityTraits(rawValue: 2)
    public static let isSelected = AccessibilityTraits(rawValue: 4)
    public static let isImage = AccessibilityTraits(rawValue: 8)
    public static let isStaticText = AccessibilityTraits(rawValue: 16)
    public static let isLink = AccessibilityTraits(rawValue: 32)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 64)
}
extension View {
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func accessibilityValue(_ value: String) -> some View { self }
    public func accessibilityHint(_ hint: String) -> some View { self }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { self }
    public func accessibilityHidden(_ hidden: Bool) -> some View { self }
}

// GAP:Text(verbatim:)
extension Text { public init(verbatim content: String) { self.init(content) } }

// GAP:State(initialValue:)
extension State { public init(initialValue: Value) { self.init(wrappedValue: initialValue) } }

// GAP:VerticalAlignment.firstTextBaseline
extension VerticalAlignment {
    public static var firstTextBaseline: VerticalAlignment { .center }
    public static var lastTextBaseline: VerticalAlignment { .center }
}

// GAP:Font.Weight cases beyond regular/medium/semibold/bold, Font.width
extension Font.Weight {
    public static var heavy: Font.Weight { .bold }
    public static var black: Font.Weight { .bold }
    public static var light: Font.Weight { .regular }
    public static var thin: Font.Weight { .regular }
    public static var ultraLight: Font.Weight { .regular }
}
extension Font {
    public struct Width: Sendable { public static let condensed = Width(); public static let standard = Width(); public static let expanded = Width() }
    public func width(_ width: Width) -> Font { self }
}

// GAP:Scene / WindowGroup
public protocol Scene {}
public struct WindowGroup<Content: View>: Scene {
    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {}
}

// GAP:ViewModifier
public struct _ViewModifier_Content<M>: View { @MainActor public var body: Never { return fatalError() } }
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor func body(content: Content) -> Body
}
extension View { public func modifier<M: ViewModifier>(_ modifier: M) -> some View { self } }

// GAP:layoutPriority
extension View { public func layoutPriority(_ value: Double) -> some View { self } }

// GAP:View.id(_:)
extension View { public func id<ID: Hashable>(_ id: ID) -> some View { self } }

// GAP:TextField(_:text:axis:) (multi-line field)
extension TextField where Label == Text {
    public init(_ titleKey: String, text: Binding<String>, axis: Axis) { self.init(titleKey, text: text) }
}

// PLATFORM-GAP (Foundation on Windows, not SwiftRight): RelativeDateTimeFormatter is not in swift-corelibs-foundation here
public final class RelativeDateTimeFormatter {
    public enum UnitsStyle { case full, spellOut, short, abbreviated }
    public var unitsStyle: UnitsStyle = .full
    public init() {}
    public func localizedString(for date: Date, relativeTo reference: Date) -> String { "" }
}
