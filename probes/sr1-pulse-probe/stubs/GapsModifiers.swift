import Foundation
import SwiftRightUI
// GAP-FILL (modifiers/extensions): declaration-only. Dropped by NOMODS=1 to enumerate missing modifiers.
// ---- layer 2: modifiers (all on View) ----
extension View {
    func foregroundStyle(_ c: Color) -> some View { self }
    func foregroundColor(_ c: Color?) -> some View { self }
    func font(_ f: Font) -> some View { self }
    func fontWeight(_ w: FontWeight) -> some View { self }
    func transition(_ t: AnyTransition) -> some View { self }
    func glassEffect<S: Shape>(_ g: Int, in s: S) -> some View { self }
    func lineLimit(_ n: Int) -> some View { self }
    func minimumScaleFactor(_ f: CGFloat) -> some View { self }
    func fixedSize(horizontal: Bool, vertical: Bool) -> some View { self }
    func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .leading) -> some View { self }
    func frame(maxWidth: CGFloat, alignment: Alignment = .leading) -> some View { self }
    func padding(_ length: CGFloat) -> some View { self }
    func background<V: View>(_ v: V) -> some View { self }
    func background<V: View>(@ViewBuilder _ v: () -> V) -> some View { self }
    func overlay<V: View>(_ v: V) -> some View { self }
    func overlay<V: View>(@ViewBuilder _ v: () -> V) -> some View { self }
    func clipShape<S: Shape>(_ s: S) -> some View { self }
    func contentShape<S: Shape>(_ s: S) -> some View { self }
    func onTapGesture(perform: @escaping () -> Void) -> some View { self }
    func buttonStyle<S>(_ s: S) -> some View { self }
    func offset(x: CGFloat, y: CGFloat) -> some View { self }
    func scaleEffect(_ s: CGFloat) -> some View { self }
    func rotationEffect(_ a: Angle) -> some View { self }
    func onChange<V: Equatable>(of v: V, perform: @escaping (V, V) -> Void) -> some View { self }
    func layoutPriority(_ p: Double) -> some View { self }
    func monospacedDigit() -> some View { self }
    func id<I: Hashable>(_ i: I) -> some View { self }
    func accessibilityElement(children: AccessibilityChildBehavior) -> some View { self }
    func contentTransition(_ t: ContentTransition) -> some View { self }
    func accessibilityLabel(_ s: String) -> some View { self }
}


extension Animation {
    static func spring(response: Double, dampingFraction: Double) -> Animation { Animation() }
    static func timingCurve(_ a: Double, _ b: Double, _ c: Double, _ d: Double, duration: Double) -> Animation { Animation() }
    static func easeInOut(duration: Double) -> Animation { Animation() }
    func repeatForever(autoreverses: Bool) -> Animation { self }
}

extension VerticalAlignment { static var firstTextBaseline: VerticalAlignment { .center } }

extension Text {
    func foregroundColor(_ c: Color?) -> Text { self }
}
