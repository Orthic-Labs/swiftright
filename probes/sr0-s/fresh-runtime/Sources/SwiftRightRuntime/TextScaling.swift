import Foundation

// SR2 block R5 (issue #40, docs/sr2-plan.md): `minimumScaleFactor` and the View-level `monospacedDigit()`.
//
// minimumScaleFactor: a one-line Text whose natural width exceeds its proposal shrinks its font until it fits, down to `factor` x the size. The runtime
// shrinks a sized font (`.system(size:)`, `.custom(_:size:)`) in half-point steps (the measurer's metric table holds half points), so it can end up to 0.5 pt
// smaller than SwiftUI's continuous size; a text-style font (`.body`, ...) has no point size in the runtime and is not shrunk (it is truncated as before).
// The layout records which font produced each measured size, and the resolved node carries the font of its placed size, so the host draws what was measured.

private enum MinimumScaleFactorKey: EnvironmentKey {
    static var defaultValue: CGFloat { 1 }
}

private enum MonospacedDigitKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// `.minimumScaleFactor(_:)`: how far a one-line Text may shrink to fit (1: not at all).
    public var minimumScaleFactor: CGFloat {
        get { self[MinimumScaleFactorKey.self] }
        set { self[MinimumScaleFactorKey.self] = newValue }
    }

    /// The View-level `.monospacedDigit()`: text below uses tabular figures.
    var monospacedDigitRequested: Bool {
        get { self[MonospacedDigitKey.self] }
        set { self[MonospacedDigitKey.self] = newValue }
    }

    /// The font a Text below draws with: the environment font, with tabular figures when `.monospacedDigit()` is in effect.
    var textFont: Font? {
        guard monospacedDigitRequested else { return font }
        return (font ?? .body).monospacedDigit()
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:)
    public func minimumScaleFactor(_ factor: CGFloat) -> some View {
        environment(\.minimumScaleFactor, min(max(factor, 0.01), 1))
    }

    /// Tabular figures for the text below (the environment font's `monospacedDigit()`). Apple: https://developer.apple.com/documentation/swiftui/view/monospaceddigit()
    public func monospacedDigit() -> some View {
        environment(\.monospacedDigitRequested, true)
    }
}

extension Font {
    /// This font at `pointSize`, keeping family, weight, design, width and figures; nil for a text-style font (no point size here).
    func sized(_ pointSize: CGFloat) -> Font? {
        guard let m = metadata, let size = m.pointSize, m.textStyle == nil, size != pointSize else { return metadata?.pointSize == pointSize ? self : nil }
        return Font(id: "\(id)|size(\(pointSize))",
                    metadata: Metadata(familyName: m.familyName, pointSize: pointSize, weight: m.weight, design: m.design, isCustom: m.isCustom,
                                       textStyle: nil, width: m.width, isEmphasized: m.isEmphasized, monospacedDigit: m.monospacedDigit))
    }
}
