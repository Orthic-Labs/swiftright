import Foundation

// Slider (SR1 round 6, block 37; decisions H1, H2 and the H4+ series in docs/sr1-decisions.md).
//
// Anatomy and metrics, measured on macOS 27 at scale 2.5 (factory/pipeline/blocks-37-38):
//   - the control is 16 pt high and as wide as it is offered (ideal 30 pt: the 20 pt thumb plus 10); its thumb is 20 x 16 pt;
//   - a leading label (`label:`) is drawn before the control with 8 pt between; the minimum and maximum value labels sit at the two ends of the
//     track with 4 pt between each and the track; the track takes what the labels leave;
//   - a click on the track puts the thumb's centre at the pointer (clamped, snapped to the step); a press on the thumb grabs it where it was
//     pressed; the arrow keys and the accessibility increment move the value by `step` when there is one, else by a tenth of the range.
// The runtime owns the model (value, bounds, step, the track rectangle); the host paints (`SliderArtwork` in SwiftRightHost).

/// What a Slider reads and writes, type-erased over the bound floating-point type.
struct SliderSpec {
    let read: () -> Double
    let write: (Double) -> Void
    let lower: Double
    let upper: Double
    let step: Double?
    let onEditing: (Bool) -> Void
    let hasLabel: Bool
    let hasValueLabels: Bool

    /// Control height and thumb width, in points.
    static let height: CGFloat = 16
    static let thumbWidth: CGFloat = 20
    static let idealTrackWidth: CGFloat = 30
    static let labelSpacing: CGFloat = 8
    static let valueLabelSpacing: CGFloat = 4

    var span: Double { upper - lower }

    func clamped(_ v: Double) -> Double {
        guard v.isFinite else { return lower }
        return min(max(v, lower), upper)
    }

    /// The nearest multiple of `step` counted from `lower` (ties go up), clamped; without a step the clamped value.
    func snapped(_ v: Double) -> Double {
        let c = clamped(v)
        guard let step, step > 0, span > 0 else { return c }
        let n = ((c - lower) / step).rounded(.toNearestOrAwayFromZero)
        return clamped(lower + n * step)
    }

    /// The change one arrow key makes (and the accessibility increment): the step, else a tenth of the range.
    var increment: Double { step ?? span / 10 }
    /// The change PageUp / PageDown make: a tenth of the range, never less than the increment.
    var largeIncrement: Double { max(increment, span / 10) }
}

/// A slider's state for the host and for accessibility.
public struct ResolvedSlider: Equatable, Sendable {
    public let value: Double
    public let lower: Double
    public let upper: Double
    public let step: Double?
    /// The control (track and thumb) in logical points and in device pixels, window coordinates; labels are outside it.
    public let trackFrame: LayoutRect
    public let trackPixelFrame: PixelRect
    public let isFocused: Bool
    /// The thumb's left edge from the track's left edge, in device pixels: `floor(t * (width - thumb) + 0.5)` (decision H2).
    public let thumbOffsetPixels: Int
    /// UIA RangeValue SmallChange / LargeChange.
    public let smallChange: Double
    public let largeChange: Double
    /// (value - lower) / (upper - lower), 0 for an empty range.
    public var fraction: Double { upper > lower ? (value - lower) / (upper - lower) : 0 }
}

@MainActor
public struct Slider<Label: View, ValueLabel: View>: View, PrimitiveView {
    let spec: SliderSpec
    let label: Label?
    let minimumValueLabel: ValueLabel?
    let maximumValueLabel: ValueLabel?

    init<V: BinaryFloatingPoint>(value: Binding<V>, bounds: ClosedRange<V>, step: V?, onEditingChanged: @escaping (Bool) -> Void,
                                 label: Label?, minimumValueLabel: ValueLabel?, maximumValueLabel: ValueLabel?) where V.Stride: BinaryFloatingPoint {
        spec = SliderSpec(read: { Double(value.wrappedValue) }, write: { value.wrappedValue = V($0) },
                          lower: Double(bounds.lowerBound), upper: Double(bounds.upperBound), step: step.map { Double($0) },
                          onEditing: onEditingChanged, hasLabel: label != nil, hasValueLabels: minimumValueLabel != nil)
        self.label = label
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .slider(spec) }
    var nodeContent: (any View)? {
        // children in order: the label, the minimum value label, the maximum value label (those that exist)
        var listed: [any View] = []
        if let label { listed.append(label) }
        if let minimumValueLabel, let maximumValueLabel {
            listed.append(minimumValueLabel.font(Font.system(size: 11)).foregroundStyle(Color.secondary))
            listed.append(maximumValueLabel.font(Font.system(size: 11)).foregroundStyle(Color.secondary))
        }
        if listed.isEmpty { return nil }
        if listed.count == 1 { return listed[0] }
        return TupleView<[any View]>(value: listed, listed: listed)
    }
}

// SwiftUI's initialisers (Apple: https://developer.apple.com/documentation/swiftui/slider). Both orders of the label closures exist.
extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: nil, onEditingChanged: onEditingChanged, label: nil, minimumValueLabel: nil, maximumValueLabel: nil)
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: V(step), onEditingChanged: onEditingChanged, label: nil, minimumValueLabel: nil, maximumValueLabel: nil)
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                        @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: nil, onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: nil, maximumValueLabel: nil)
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                        @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: V(step), onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: nil, maximumValueLabel: nil)
    }
}

extension Slider {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: nil, onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: V(step), onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: nil, onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel())
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
        self.init(value: value, bounds: bounds, step: V(step), onEditingChanged: onEditingChanged, label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel())
    }
}

extension Slider: @MainActor LabeledControl {
    var titleView: any View { label ?? EmptyView() }
}

// MARK: - Interaction (the host routes pointer, keys and accessibility actions here)

extension Graph {
    /// The model of a live slider, for tests and hosts.
    public func sliderModel(_ id: String) -> (value: Double, lower: Double, upper: Double, step: Double?)? {
        guard let n = node(id), case .slider(let spec) = n.kind else { return nil }
        return (spec.clamped(spec.read()), spec.lower, spec.upper, spec.step)
    }

    /// The value a pointer at `x` (logical points, window coordinates) selects on the slider's track: the thumb's centre follows the pointer,
    /// less the grab offset of a drag that began on the thumb.
    func sliderValue(at x: CGFloat, spec: SliderSpec, track: LayoutRect, grab: CGFloat) -> Double {
        let travel = max(1, track.width - SliderSpec.thumbWidth)
        let t = min(max((x - grab - track.minX - SliderSpec.thumbWidth / 2) / travel, 0), 1)
        return spec.snapped(spec.lower + Double(t) * spec.span)
    }

    /// Gives the slider the keyboard (a press on it): one node holds the implicit focus.
    private func focusSlider(_ node: Node) {
        for other in nodes.values where other.alive && other.focused && other !== node {
            if case .textField = other.kind { other.focused = false }
            if case .slider = other.kind { other.focused = false }
        }
        node.focused = true
    }

    /// A pointer press at `x` (logical points) on a live, enabled slider: it takes the focus, `onEditingChanged(true)` runs and the value follows
    /// the pointer. Returns false when `id` is not a live enabled slider.
    @discardableResult
    public func sliderPress(_ id: String, atX x: CGFloat) -> Bool {
        guard let n = node(id), case .slider(let spec) = n.kind, n.alive, n.environment.isEnabled else { return false }
        focusSlider(n)
        let track = n.sliderTrack
        let value = spec.clamped(spec.read())
        let thumbCentre = track.minX + SliderSpec.thumbWidth / 2 + CGFloat(spec.span > 0 ? (value - spec.lower) / spec.span : 0) * max(1, track.width - SliderSpec.thumbWidth)
        // a press on the thumb grabs it where it was pressed; a press elsewhere on the track puts the thumb's centre at the pointer
        n.sliderGrab = abs(x - thumbCentre) <= SliderSpec.thumbWidth / 2 ? x - thumbCentre : 0
        n.sliderDragging = true
        spec.onEditing(true)
        let next = sliderValue(at: x, spec: spec, track: track, grab: n.sliderGrab)
        if next != value { spec.write(next) }
        flush()
        return true
    }

    /// The pointer moved with the button down.
    @discardableResult
    public func sliderDrag(_ id: String, toX x: CGFloat) -> Bool {
        guard let n = node(id), case .slider(let spec) = n.kind, n.alive, n.sliderDragging, n.environment.isEnabled else { return false }
        let next = sliderValue(at: x, spec: spec, track: n.sliderTrack, grab: n.sliderGrab)
        if next != spec.clamped(spec.read()) { spec.write(next) }
        flush()
        return true
    }

    /// The button went up: `onEditingChanged(false)`.
    @discardableResult
    public func sliderRelease(_ id: String) -> Bool {
        guard let n = node(id), case .slider(let spec) = n.kind, n.alive, n.sliderDragging else { return false }
        n.sliderDragging = false
        n.sliderGrab = 0
        spec.onEditing(false)
        flush()
        return true
    }

    /// An arrow key or an accessibility increment/decrement: the value moves by `steps` increments (`large`: by the large increment, PageUp/PageDown),
    /// clamped and snapped, between `onEditingChanged(true)` and `(false)`. Returns false when `id` is not a live enabled slider.
    @discardableResult
    public func sliderAdjust(_ id: String, by steps: Int, large: Bool = false) -> Bool {
        guard let n = node(id), case .slider(let spec) = n.kind, n.alive, n.environment.isEnabled else { return false }
        let value = spec.clamped(spec.read())
        let next = spec.snapped(value + Double(steps) * (large ? spec.largeIncrement : spec.increment))
        spec.onEditing(true)
        if next != value { spec.write(next) }
        spec.onEditing(false)
        flush()
        return true
    }

    /// Home / End: the lower / upper bound.
    @discardableResult
    public func sliderSet(_ id: String, toBound upper: Bool) -> Bool {
        guard let n = node(id), case .slider(let spec) = n.kind, n.alive, n.environment.isEnabled else { return false }
        let value = spec.clamped(spec.read()), next = upper ? spec.upper : spec.lower
        spec.onEditing(true)
        if next != value { spec.write(next) }
        spec.onEditing(false)
        flush()
        return true
    }

    /// The runtime id of the slider that holds the keyboard, nil when none does.
    public var focusedSliderID: String? {
        for n in nodes.values where n.alive && n.focused { if case .slider = n.kind { return n.idString } }
        return nil
    }

    /// The thumb's left edge from the track's left edge in device pixels (decision H2).
    public static func thumbOffsetPixels(fraction: Double, trackPixelWidth: Int, thumbPixels: Int) -> Int {
        let travel = Double(max(0, trackPixelWidth - thumbPixels))
        return Int((fraction * travel + 0.5).rounded(.down))
    }

    func resolveSlider(_ node: Node, spec: SliderSpec) -> ResolvedSlider {
        let value = spec.clamped(spec.read())
        let track = node.sliderTrack
        let pixel = pixelRect(track, scale: scale)
        let thumbPixels = Int((SliderSpec.thumbWidth * scale).rounded())
        let fraction = spec.span > 0 ? (value - spec.lower) / spec.span : 0
        return ResolvedSlider(value: value, lower: spec.lower, upper: spec.upper, step: spec.step, trackFrame: track, trackPixelFrame: pixel,
                              isFocused: node.focused, thumbOffsetPixels: Self.thumbOffsetPixels(fraction: fraction, trackPixelWidth: Int(pixel.width), thumbPixels: thumbPixels),
                              smallChange: spec.increment, largeChange: spec.largeIncrement)
    }
}
