import Foundation

// One witness source maps current runtime geometry names to Apple Layout names.
// Windows package keeps runtime LayoutSize/LayoutRect/LayoutPoint; this Mac
// packet keeps same layout algorithm against Apple CGSize/CGRect/CGPoint.
#if os(Windows)
import SwiftRightRuntime
typealias AppleLayout = SwiftRightRuntime.Layout
typealias AppleProposedViewSize = SwiftRightRuntime.ProposedViewSize
typealias AppleLayoutSize = SwiftRightRuntime.LayoutSize
typealias AppleLayoutRect = SwiftRightRuntime.LayoutRect
typealias AppleLayoutPoint = SwiftRightRuntime.LayoutPoint
#else
import SwiftUI
typealias AppleLayout = SwiftUI.Layout
typealias AppleProposedViewSize = SwiftUI.ProposedViewSize
typealias AppleLayoutSize = CGSize
typealias AppleLayoutRect = CGRect
typealias AppleLayoutPoint = CGPoint
#endif

struct Witness_custom_layout: View {
    var body: some View {
        WitnessMeasuredLayout(spacing: 4) {
            ForEach(0..<1, id: \.self) { index in
                Color.red.frame(width: 12 + CGFloat(index) * 4,
                                height: 10 + CGFloat(index) * 4)
            }
        }
        .frame(width: 32, height: 32)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct WitnessMeasuredLayout: AppleLayout {
    var spacing: CGFloat

    func sizeThatFits(proposal: AppleProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> AppleLayoutSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.reduce(0) { $0 + $1.width }
            + spacing * CGFloat(max(0, sizes.count - 1))
        let height = sizes.map(\.height).max() ?? 0
        return AppleLayoutSize(width: width, height: height)
    }

    func placeSubviews(in bounds: AppleLayoutRect,
                       proposal: AppleProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: AppleLayoutPoint(x: x, y: bounds.minY),
                          proposal: AppleProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
