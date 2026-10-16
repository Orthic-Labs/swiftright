import SwiftRightBridge

/// The window a host opens (decision H17). The public window/app entry of SwiftRightHost: one value carries everything the
/// renderer needs at run time, and `Bridge.run(_:)` passes it through unchanged.
public struct HostWindowOptions: Equatable {
    public var title: String
    /// Initial client size in DIPs (device-independent pixels at 96 dpi).
    public var width: UInt32
    public var height: UInt32
    /// Ask for hover and drag pointer events (needs a 0.9 renderer; ignored below that).
    public var pointerMoves: Bool
    /// An explicit render scale: a device scale factor used instead of the window's DPI, for fixed-scale exports and the same
    /// rendering on every display (2.5 is 240 dpi). The client area is `width * renderScale` by `height * renderScale` physical
    /// pixels, text is measured and rasterised at it, and the window's metrics report it. nil keeps the window's DPI. Needs a 0.10
    /// renderer: a renderer without it makes `run` throw, never ignore. If the window moves to a display with a different DPI the
    /// scale stays `renderScale`; the window's physical size follows the OS and the host re-measures on the metrics event.
    public var renderScale: Float?

    public init(title: String, width: UInt32, height: UInt32, pointerMoves: Bool = false, renderScale: Float? = nil) {
        self.title = title
        self.width = width
        self.height = height
        self.pointerMoves = pointerMoves
        self.renderScale = renderScale
    }
}

public extension Bridge {
    /// Opens the window described by `options` and runs the renderer loop (see `Bridge.run(title:width:height:pointerMoves:renderScale:)`).
    @discardableResult
    func run(_ options: HostWindowOptions) throws -> Int32 {
        try HostWindowOptions.forward(options) { title, width, height, pointerMoves, renderScale in
            try run(title: title, width: width, height: height, pointerMoves: pointerMoves, renderScale: renderScale)
        }
    }
}

extension HostWindowOptions {
    /// The one place the options become `Bridge.run` arguments. A seam for tests: every field is passed through, none is derived.
    static func forward(_ o: HostWindowOptions, _ run: (String, UInt32, UInt32, Bool, Float?) throws -> Int32) rethrows -> Int32 {
        try run(o.title, o.width, o.height, o.pointerMoves, o.renderScale)
    }
}
