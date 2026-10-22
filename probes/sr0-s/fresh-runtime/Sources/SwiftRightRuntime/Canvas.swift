import Foundation

// Issue #82 (SR2 S2): Canvas and GraphicsContext, as retained drawing: the renderer closure runs when the view is evaluated (with the size layout gave it), records
// each `fill` and `stroke` of a path, and the canvas is those paths stacked in drawing order in a view of that size, so they paint through the shape pipeline.
// Supported: fill / stroke (colour and `ShapeStyle` shadings, line width or StrokeStyle), translateBy / scaleBy / rotate / concatenate, opacity (multiplied into the colours drawn after it),
// clip(to:) is not supported and `draw(Text/Image)`, filters, layers, symbols and `resolve` are not modelled. A Canvas is not an accessibility element.

/// Apple: https://developer.apple.com/documentation/swiftui/graphicscontext
public struct GraphicsContext {
    /// Apple: https://developer.apple.com/documentation/swiftui/graphicscontext/shading
    public struct Shading {
        let color: ResolvedColor
        public static func color(_ color: Color) -> Shading { Shading(color: color.resolvedColor) }
        public static func style<S: ShapeStyle>(_ style: S) -> Shading { Shading(color: style.resolvedColor) }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            Shading(color: Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity).resolvedColor)
        }
        public static func color(white: Double, opacity: Double = 1) -> Shading { Shading(color: Color(white: white, opacity: opacity).resolvedColor) }
    }

    final class Recording { var views: [@MainActor () -> AnyView] = [] }
    let recording: Recording
    private var transform: CGAffineTransform = .identity
    public var opacity: Double = 1

    init(_ recording: Recording) { self.recording = recording }

    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = CGAffineTransform(translationX: x, y: y).concatenating(transform) }
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = CGAffineTransform(scaleX: x, y: y).concatenating(transform) }
    public mutating func rotate(by angle: Angle) { transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians)).concatenating(transform) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }

    private func shading(_ s: Shading) -> Color { Color(resolved: opacity < 1 ? s.color.multiplied(by: opacity) : s.color) }

    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        let p = path.applying(transform), s = self.shading(shading)
        recording.views.append { AnyView(p.fill(s, style: style)) }
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        let p = path.applying(transform), s = self.shading(shading)
        recording.views.append { AnyView(p.stroke(s, lineWidth: lineWidth)) }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        let p = path.applying(transform), s = self.shading(shading)
        recording.views.append { AnyView(p.stroke(s, style: style)) }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/canvas
public struct Canvas: View {
    let renderer: (inout GraphicsContext, CGSize) -> Void

    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.renderer = renderer
    }

    @MainActor public var body: some View {
        GeometryReader { proxy in
            let recording = GraphicsContext.Recording()
            let _: Void = {
                var context = GraphicsContext(recording)
                renderer(&context, proxy.size)
            }()
            ZStack(alignment: .topLeading) {
                ForEach(Array(recording.views.enumerated()), id: \.offset) { $0.element() }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/colorrenderingmode
public enum ColorRenderingMode: Sendable { case nonLinear, linear, extendedLinear }
