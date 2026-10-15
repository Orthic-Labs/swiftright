// Probe-only patch, added to a COPY of the staged runtime (never to the product tree). Minimal working versions of the gaps whose
// absence stops the hub from compiling AND from drawing: AnyView, single-child ViewBuilder identity, Color.opacity(_:) -> Color, Color.clear.
// Written against the runtime's internals (PrimitiveView/ViewContainer/Segment), so it shows what a real block would touch.
import Foundation

// GAP:AnyView -- a transparent container: the wrapped view is spliced in as its only child.
public struct AnyView: View, ViewContainer {
    nonisolated(unsafe) let inner: any View
    public nonisolated init<V: View>(_ view: V) { inner = view }
    @MainActor public var body: Never { return fatalError("AnyView has no body") }
    @MainActor func parts() -> [(Segment, any View)] { [(.index(0), inner)] }
}

// GAP:ViewBuilder.buildBlock(_:) returns its single child unchanged (SwiftUI does; the runtime wraps it in TupleView)
extension ViewBuilder {
    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
}

// GAP:Color.opacity(_:) -> Color (the runtime's Color.opacity is the View modifier) and Color.clear
extension Color {
    public func opacity(_ opacity: Double) -> Color {
        if case .rgba(let r, let g, let b, let a) = resolvedColor { return Color(red: r, green: g, blue: b, opacity: a * opacity) }
        if case .semantic(let name) = resolvedColor {   // the two semantic colours the hub dims (hit areas, scrims)
            if name == "black" { return Color(red: 0, green: 0, blue: 0, opacity: opacity) }
            if name == "white" { return Color(red: 1, green: 1, blue: 1, opacity: opacity) }
        }
        return self   // other semantic colours keep full alpha (probe limitation)
    }
}
extension ShapeStyle where Self == Color { public static var clear: Color { Color(red: 0, green: 0, blue: 0, opacity: 0) } }
