import Foundation

// Issue #68 (MarkdownUI on SwiftRight): anchors, anchor preferences and the preference-value layers.
//
//   Anchor<Value>                     a place in a view (its bounds, or a point of them), resolved later against a GeometryProxy
//   anchorPreference(key:value:transform:)   contributes `transform(anchor)` for the modified view's frame, like `preference(key:value:)`
//   backgroundPreferenceValue / overlayPreferenceValue   a layer built from the preference value the view's subtree reduces to
//   GeometryProxy[anchor]             the anchor's value in the proxy's local coordinate space
//
// An anchor holds a frame box that layout keeps current (`Graph.place`), not the node, so resolving one needs no actor hop. A GeometryReader that resolves anchors logs the
// frames it read; the graph rebuilds the reader's content when any of them moves (an anchored view can move without the reader's size or origin changing).

/// The laid-out frame (graph coordinates) of the view an anchor was made for. Updated by layout.
final class AnchorFrameBox: @unchecked Sendable {
    var rect: CGRect = .zero
}

/// The anchored frames a GeometryReader's content resolved, to notice when one moved.
final class AnchorReadLog: @unchecked Sendable {
    private var reads: [(box: AnchorFrameBox, rect: CGRect)] = []

    func record(_ box: AnchorFrameBox, _ rect: CGRect) {
        reads.append((box, rect))
    }

    var isStale: Bool { reads.contains { $0.box.rect != $0.rect } }
}

/// A place in a view, resolved against a `GeometryProxy` with `proxy[anchor]`.
/// Apple: https://developer.apple.com/documentation/swiftui/anchor
public struct Anchor<Value> {
    let box: AnchorFrameBox
    let source: Source

    /// Which part of the view an anchor names.
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source
    public struct Source {
        let resolve: @Sendable (CGRect) -> Value
        init(resolve: @escaping @Sendable (CGRect) -> Value) { self.resolve = resolve }
    }
}

extension Anchor: Hashable {
    /// Two anchors are equal when they name the same view's frame.
    public static func == (lhs: Anchor<Value>, rhs: Anchor<Value>) -> Bool { lhs.box === rhs.box }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(box)) }
}

extension Anchor.Source where Value == CGRect {
    /// The view's bounds. Apple: https://developer.apple.com/documentation/swiftui/anchor/source/bounds
    public static var bounds: Anchor<CGRect>.Source { Anchor<CGRect>.Source(resolve: { $0 }) }

    /// A rectangle in the view's own coordinates. Apple: https://developer.apple.com/documentation/swiftui/anchor/source/rect(_:)
    public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source {
        Anchor<CGRect>.Source(resolve: { CGRect(x: $0.minX + r.minX, y: $0.minY + r.minY, width: r.width, height: r.height) })
    }
}

extension Anchor.Source where Value == CGPoint {
    /// A point of the view's bounds given as a unit point. Apple: https://developer.apple.com/documentation/swiftui/anchor/source/unitpoint(_:)
    public static func unitPoint(_ p: UnitPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source(resolve: { CGPoint(x: $0.minX + p.x * $0.width, y: $0.minY + p.y * $0.height) })
    }

    /// A point in the view's own coordinates. Apple: https://developer.apple.com/documentation/swiftui/anchor/source/point(_:)
    public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source(resolve: { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) })
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/topleading
    public static var topLeading: Anchor<CGPoint>.Source { unitPoint(.topLeading) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/top
    public static var top: Anchor<CGPoint>.Source { unitPoint(.top) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/toptrailing
    public static var topTrailing: Anchor<CGPoint>.Source { unitPoint(.topTrailing) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/leading
    public static var leading: Anchor<CGPoint>.Source { unitPoint(.leading) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/center
    public static var center: Anchor<CGPoint>.Source { unitPoint(.center) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/trailing
    public static var trailing: Anchor<CGPoint>.Source { unitPoint(.trailing) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/bottomleading
    public static var bottomLeading: Anchor<CGPoint>.Source { unitPoint(.bottomLeading) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/bottom
    public static var bottom: Anchor<CGPoint>.Source { unitPoint(.bottom) }
    /// Apple: https://developer.apple.com/documentation/swiftui/anchor/source/bottomtrailing
    public static var bottomTrailing: Anchor<CGPoint>.Source { unitPoint(.bottomTrailing) }
}

extension GeometryProxy {
    /// The anchor's value in this reader's local coordinate space (origin at the reader's top-leading corner). An anchor whose view has not been laid out reads as the zero rect.
    /// Apple: https://developer.apple.com/documentation/swiftui/geometryproxy/subscript(_:)
    public subscript<T>(anchor: Anchor<T>) -> T {
        let global = anchor.box.rect
        reads?.record(anchor.box, global)
        let local = CGRect(x: global.minX - globalOrigin.x, y: global.minY - globalOrigin.y, width: global.width, height: global.height)
        return anchor.source.resolve(local)
    }
}

extension Node {
    /// The frame box of this node, made on first use and filled from the current frame.
    func ensureAnchorBox() -> AnchorFrameBox {
        if let box = anchorBox { return box }
        let box = AnchorFrameBox()
        box.rect = frame.cgRect
        anchorBox = box
        return box
    }
}

extension View {
    /// Adds `transform(anchor)` to the upward preference stream for `key`, where the anchor names `value` of this view. The view's layout is unchanged.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/anchorpreference(key:value:transform:)
    public func anchorPreference<A, K: PreferenceKey>(
        key _: K.Type = K.self,
        value: Anchor<A>.Source,
        transform: @escaping (Anchor<A>) -> K.Value
    ) -> some View {
        Modified(content: self, spec: .preference(PreferenceContribution(for: K.self) { node in
            transform(Anchor<A>(box: node.ensureAnchorBox(), source: value))
        }))
    }

    /// A layer behind this view built from the value `key` reduces to over this view. The layer is aligned in the view's frame and sized to it, as `background(alignment:content:)`.
    /// Approximation: the layer sees `Key.defaultValue` until the first reduction is delivered (one extra evaluation round), and a value that is not `Equatable` is delivered once.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/backgroundpreferencevalue(_:alignment:_:)
    public func backgroundPreferenceValue<Key: PreferenceKey, V: View>(
        _ key: Key.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Key.Value) -> V
    ) -> some View {
        PreferenceValueLayer<Key, Self, V>(isOverlay: false, alignment: alignment, base: self, transform: transform)
    }

    /// A layer in front of this view built from the value `key` reduces to over this view; see `backgroundPreferenceValue`.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/overlaypreferencevalue(_:alignment:_:)
    public func overlayPreferenceValue<Key: PreferenceKey, V: View>(
        _ key: Key.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Key.Value) -> V
    ) -> some View {
        PreferenceValueLayer<Key, Self, V>(isOverlay: true, alignment: alignment, base: self, transform: transform)
    }
}

/// `x == y` for two values of one `Equatable` type held as `Any`; true (never "changed") for values that are not `Equatable`.
func dynamicEquals(_ a: Any, _ b: Any) -> Bool {
    guard let lhs = a as? any Equatable else { return true }
    return openedEquals(lhs, b)
}

private func openedEquals<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
    guard let rhs = rhs as? T else { return false }
    return lhs == rhs
}

/// The view `backgroundPreferenceValue` and `overlayPreferenceValue` return: the base, observed for `Key`, with a layer built from the last delivered value.
struct PreferenceValueLayer<Key: PreferenceKey, Base: View, Layer: View>: View {
    let isOverlay: Bool
    let alignment: Alignment
    let base: Base
    let transform: (Key.Value) -> Layer
    @State private var value: Key.Value = Key.defaultValue

    var body: some View {
        let state = _value
        let observed = Modified(content: base, spec: .onPreferenceChange(
            PreferenceObserver(Key.self, equals: dynamicEquals, action: { state.wrappedValue = $0 })
        ))
        if isOverlay {
            observed.overlay(alignment: alignment) { transform(value) }
        } else {
            observed.background(alignment: alignment) { transform(value) }
        }
    }
}

#if !canImport(CoreGraphics)
/// CoreGraphics compatibility: the smallest rectangle containing both (`CGRect.null` is the identity). On Apple platforms CoreGraphics provides this function.
public func CGRectUnion(_ r1: CGRect, _ r2: CGRect) -> CGRect {
    if r1.isNull { return r2 }
    if r2.isNull { return r1 }
    let minX = min(r1.minX, r2.minX), minY = min(r1.minY, r2.minY)
    let maxX = max(r1.maxX, r2.maxX), maxY = max(r1.maxY, r2.maxY)
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
#endif

/// SwiftUI's anchors are Sendable values; the frame box is written on the main actor only.
extension Anchor: @unchecked Sendable {}
extension Anchor.Source: @unchecked Sendable {}
