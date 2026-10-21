import Foundation

// Issue #60 (SR1 backlog), passes 1 and 2: ProgressView, composed from existing primitives (shapes, GeometryReader, stacks, `.rotationEffect`). No host painting is needed.
//
// Linear-bar metrics are MEASURED from the macOS 27 capture of progress-determinate-v1 (CI 39583112762, scale 2.5, 200 pt wide bars at 0.3 and 0.7); the circular spinner is still a guess:
//   - linear bar: 8 pt tall (20 px), centred in a 19.6 pt tall view (49 px: two views 18 pt apart are 94 px between bar tops); the track is a capsule of 240 grey with a 1 px
//     (0.4 pt) edge of 223 and a second 1 px ring of 235 (layered capsules, drawn as primary at 0.148, 0.0926 and 0.0694 over white); the fill is a capsule in the tint (accent
//     0,122,255), full height, drawn over the track edge, 0.8 pt (2 px) shorter than fraction x width; track and fill span the proposed width exactly;
//   - circular (indeterminate): a 16 x 16 spinner of 12 rounded ticks (1.5 x 4 pt, from radius 4 to 8, `Color.primary`), fading from full opacity at the head to 15% at
//     the tail (the tail trails the head counter-clockwise: the head moves clockwise);
//   - a label sits above a bar, leading aligned, 4 pt apart; above or below a spinner it is 8 pt apart.
// The spinner turns by the host clock: one step of 30 degrees every 1/12 s (one turn per second, the classic NSProgressIndicator cadence; also a guess), driven by
// `ModifierSpec.spinner` (see `Graph.tick`), which is a repeat-forever driver for this control only; the runtime has no general repeating animation or TimelineView.
// The value label (`currentValueLabel`) is not modelled: `CurrentValueLabel` is always `EmptyView`.

/// A bar showing progress (`value` out of `total`) or, with no value, a spinner.
/// Apple: https://developer.apple.com/documentation/swiftui/progressview
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    /// 0...1, nil for an indeterminate view.
    let fraction: Double?
    let label: Label

    init(fraction: Double?, label: Label) {
        self.fraction = fraction
        self.label = label
    }

    /// Fraction of `value` in `0...total`, clamped; nil value or a non-positive total is indeterminate (a NaN value is 0).
    static func fractionOf<V: BinaryFloatingPoint>(value: V?, total: V) -> Double? {
        guard let value else { return nil }
        let t = Double(total)
        guard t > 0 else { return nil }
        let v = Double(value)
        guard !v.isNaN else { return 0 }
        return min(max(v / t, 0), 1)
    }

    @MainActor public var body: some View {
        ProgressViewBody(fraction: fraction, label: label, hasLabel: Label.self != EmptyView.self)
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    /// An indeterminate progress view. Apple: https://developer.apple.com/documentation/swiftui/progressview/init()
    public init() {
        self.init(fraction: nil, label: EmptyView())
    }

    /// Determinate for a value, indeterminate for nil. Apple: https://developer.apple.com/documentation/swiftui/progressview/init(value:total:)
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        self.init(fraction: Self.fractionOf(value: value, total: total), label: EmptyView())
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/progressview/init(_:)
    public init(_ title: String) {
        self.init(fraction: nil, label: Text(title))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/progressview/init(_:value:total:)
    public init<V: BinaryFloatingPoint>(_ title: String, value: V?, total: V = 1.0) {
        self.init(fraction: Self.fractionOf(value: value, total: total), label: Text(title))
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/progressview/init(label:)
    public init(@ViewBuilder label: () -> Label) {
        self.init(fraction: nil, label: label())
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/progressview/init(value:total:label:)
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ViewBuilder label: () -> Label) {
        self.init(fraction: Self.fractionOf(value: value, total: total), label: label())
    }
}

/// The composed view: [label] over a bar, or [label] and a spinner.
struct ProgressViewBody<Label: View>: View {
    let fraction: Double?
    let label: Label
    let hasLabel: Bool

    @MainActor var body: some View {
        if let fraction {
            VStack(alignment: .leading, spacing: 4) {
                if hasLabel { label }
                LinearProgressBar(fraction: fraction)
            }
        } else {
            VStack(spacing: 8) {
                IndeterminateSpinner()
                if hasLabel { label }
            }
        }
    }
}

/// Track and fill of a determinate bar: 8 pt tall inside a 19.6 pt view, as wide as it is offered.
struct LinearProgressBar: View {
    static let height: CGFloat = 8
    /// The view's own height (the bar is centred in it), measured as 49 px at scale 2.5.
    static let viewHeight: CGFloat = 19.6
    /// The fill is this much shorter than fraction x width.
    static let fillInset: CGFloat = 0.8
    /// The track's 1 px rings at scale 2.5, as `Color.primary` opacities over a white background: 223, 235 and 240 grey.
    static let ringOpacity = 32.0 / 216.0, innerRingOpacity = 20.0 / 216.0, bodyOpacity = 15.0 / 216.0
    static let ringWidth: CGFloat = 0.4
    let fraction: Double

    @MainActor var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(LinearProgressBar.ringOpacity))
            Capsule().fill(Color.primary.opacity(LinearProgressBar.innerRingOpacity)).padding(LinearProgressBar.ringWidth)
            Capsule().fill(Color.primary.opacity(LinearProgressBar.bodyOpacity)).padding(2 * LinearProgressBar.ringWidth)
            GeometryReader { proxy in
                Capsule()
                    .fill(TintShapeStyle())
                    .frame(width: max(proxy.size.width * CGFloat(fraction) - LinearProgressBar.fillInset, 0))
            }
        }
        .frame(height: LinearProgressBar.height)
        .frame(height: LinearProgressBar.viewHeight)
    }
}

extension ModifierSpec {
    /// True once any spinner view has been built in this process: `Graph.tick` only looks for spinner nodes then.
    nonisolated(unsafe) static var spinnersCreated = false
    static func noteSpinner() { spinnersCreated = true }
}

/// The indeterminate spinner: 12 ticks, 16 x 16 pt, stepped round by the host clock (see the file header).
struct IndeterminateSpinner: View {
    static let diameter: CGFloat = 16
    static let tickCount = 12
    /// Seconds per turn.
    static let period: Double = 1
    static let tickWidth: CGFloat = 1.5
    static let tickLength: CGFloat = 4
    static let tailOpacity: Double = 0.15

    /// Opacity of tick `index` (0 is the head).
    static func opacity(ofTick index: Int) -> Double {
        1 - (1 - tailOpacity) * Double(index) / Double(tickCount - 1)
    }

    @MainActor var body: some View {
        let _ = ModifierSpec.noteSpinner()
        Modified(content: ring, spec: .spinner(steps: IndeterminateSpinner.tickCount, period: IndeterminateSpinner.period))
    }

    @MainActor private var ring: some View {
        ZStack {
            ForEach(0..<IndeterminateSpinner.tickCount, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(IndeterminateSpinner.opacity(ofTick: index)))
                    .frame(width: IndeterminateSpinner.tickWidth, height: IndeterminateSpinner.tickLength)
                    .frame(width: IndeterminateSpinner.diameter, height: IndeterminateSpinner.diameter, alignment: .top)
                    .rotationEffect(.degrees(-360 * Double(index) / Double(IndeterminateSpinner.tickCount)))
            }
        }
        .frame(width: IndeterminateSpinner.diameter, height: IndeterminateSpinner.diameter)
    }
}
