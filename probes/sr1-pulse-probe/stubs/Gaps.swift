// GAP-FILL: permissive declaration-only stand-ins for SwiftUI symbols the runtime lacks, added one
// compiler diagnostic at a time so the next layer of errors becomes visible (type resolution
// hides body errors). Every declaration here IS a missing-API finding; see RESULT.md. Nothing
// here executes. Bodies are placeholders.
import Foundation
import SwiftRightUI

// ---- layer 1: types ----
struct Color: StubView, Equatable, Sendable {
    static let clear = Color(), white = Color(), black = Color(), gray = Color(), red = Color()
    static let orange = Color(), yellow = Color(), green = Color()
    func opacity(_ o: Double) -> Color { self }
}
struct Font { static let caption = Font(), headline = Font()
    static func system(size: CGFloat) -> Font { Font() } }
struct Alignment: Equatable { static let leading = Alignment(), topLeading = Alignment(), top = Alignment() }
struct Angle { static func degrees(_ d: Double) -> Angle { Angle() } }
struct Path {
    mutating func move(to: CGPoint) {}
    mutating func addCurve(to: CGPoint, control1: CGPoint, control2: CGPoint) {}
    mutating func closeSubpath() {}
    func union(_ other: Path) -> Path { self }
}
struct StrokeStyle {
    init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, dash: [CGFloat] = []) {}
}
enum CGLineCap { case butt, round }
enum RoundedCornerStyle { case circular, continuous }

protocol StubView: View {}
extension StubView { @MainActor var body: Never { fatalError() } }
protocol Shape: StubView { func path(in rect: CGRect) -> Path }
extension Shape {
    func fill(_ c: Color) -> some View { self }
    func stroke(_ c: Color, lineWidth: CGFloat = 1) -> some View { self }
    func stroke(_ c: Color, style: StrokeStyle) -> some View { self }
    func trim(from: CGFloat = 0, to: CGFloat = 1) -> some Shape { self }
    func inset(by: CGFloat) -> some Shape { self }
    func strokeBorder(_ c: Color, lineWidth: CGFloat = 1) -> some View { self }
}
struct Circle: Shape { func path(in rect: CGRect) -> Path { Path() } }
struct Rectangle: Shape { func path(in rect: CGRect) -> Path { Path() } }
struct Capsule: Shape { func path(in rect: CGRect) -> Path { Path() } }
struct RoundedRectangle: Shape {
    init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {}
    func path(in rect: CGRect) -> Path { Path() }
}
struct Group<Content: View>: StubView { init(@ViewBuilder _ c: () -> Content) {} }
struct ZStack<Content: View>: StubView { init(alignment: Alignment = .leading, @ViewBuilder content: () -> Content) {} }
struct Image: StubView { init(systemName: String) {} }
struct GeometryProxy { var size: CGSize }
struct GeometryReader<Content: View>: StubView { init(@ViewBuilder content: (GeometryProxy) -> Content) {} }
struct TimelineViewContext { var date: Date }
struct TimelineSchedule { static let animation = TimelineSchedule() }
struct TimelineView<Content: View>: StubView { init(_ s: TimelineSchedule, @ViewBuilder content: (TimelineViewContext) -> Content) {} }
protocol ButtonStyle {}
@propertyWrapper struct AppStorage<Value> { var wrappedValue: Value
    init(wrappedValue: Value, _ key: String) { self.wrappedValue = wrappedValue } }


struct AccessibilityChildBehavior { static let ignore = AccessibilityChildBehavior() }
struct ContentTransition { static func numericText() -> ContentTransition { ContentTransition() } }

struct FontWeight { static let semibold = FontWeight() }
struct AnyTransition { static let opacity = AnyTransition()
    func animation(_ a: Animation?) -> AnyTransition { self } }
