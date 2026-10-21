import Foundation

// Issue #60 (SR1 backlog), first pass: ProgressView, composed from existing primitives (shapes, GeometryReader, stacks). No host painting is needed.
//
// Metrics are GUESSED from AppKit's NSProgressIndicator, not measured on macOS 27 (the SR0 oracle has no ProgressView capture yet):
//   - linear bar: 6 pt tall, a capsule track (10% black, `Color.secondary` at 0.2), a capsule fill in the tint (accent) colour, as wide as the proposal;
//   - circular (indeterminate): a 16 x 16 ring of three quarters, 2 pt stroke, NOT animated (the runtime has no repeating animation, and a spinning ring
//     needs a host-driven clock; the host should replace the static ring with a spinner when it grows one);
//   - a label sits above a bar, leading aligned, 4 pt apart; above or below a spinner it is 8 pt apart.
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

/// Track and fill of a determinate bar: 6 pt tall, as wide as it is offered.
struct LinearProgressBar: View {
    static let height: CGFloat = 6
    let fraction: Double

    @MainActor var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.2))
            GeometryReader { proxy in
                Capsule()
                    .fill(TintShapeStyle())
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: LinearProgressBar.height)
    }
}

/// A static three-quarter ring, 16 x 16 pt (not animated; see the file header).
struct IndeterminateSpinner: View {
    static let diameter: CGFloat = 16

    @MainActor var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.secondary, lineWidth: 2)
            .frame(width: IndeterminateSpinner.diameter, height: IndeterminateSpinner.diameter)
    }
}
