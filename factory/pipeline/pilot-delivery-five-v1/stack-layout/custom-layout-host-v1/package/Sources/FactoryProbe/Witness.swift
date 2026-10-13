#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

import Foundation

struct Witness_custom_layout: View {
    var body: some View {
        WitnessMeasuredLayout(spacing: 4) {
            ForEach(0..<1, id: \.self) { index in
                Color.red.frame(width: 12 + CGFloat(index) * 4, height: 10 + CGFloat(index) * 4)
            }
        }
        .frame(width: 32, height: 32)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// Uses current 37429120 portable LayoutSize/LayoutRect witnesses. Runtime LayoutRoot
// stores this layout in LayoutEngine, then host joins ResolvedNode bounds to ABI0.6 fill.
struct WitnessMeasuredLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> LayoutSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let height = sizes.map(\.height).max() ?? 0
        return LayoutSize(width: width, height: height)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: LayoutPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
