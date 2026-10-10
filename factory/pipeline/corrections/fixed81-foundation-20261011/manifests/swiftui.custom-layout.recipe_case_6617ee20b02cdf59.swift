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
        .frame(width: 48, height: 32)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct WitnessMeasuredLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1)), height: sizes.map(\.height).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
