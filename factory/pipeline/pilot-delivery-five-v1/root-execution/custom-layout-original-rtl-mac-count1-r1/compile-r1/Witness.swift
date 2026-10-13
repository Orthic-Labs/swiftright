import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_custom_layout: View {
    var body: some View {
        WitnessMeasuredLayout(spacing: 4) {
            ForEach(0..<2, id: \.self) { index in
                Color.red.frame(width: 12 + CGFloat(index) * 4,
                                height: 10 + CGFloat(index) * 4)
            }
        }
        .frame(width: 48, height: 32)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// Same witness bytes compile against SwiftUI.Layout on Mac & runtime Layout on
// Windows. Runtime provides direct CGSize/CGRect/CGPoint overloads, so no
// aliases or host-specific algorithm branches are needed.
struct WitnessMeasuredLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let sizes: [CGSize] = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.reduce(0) { $0 + $1.width }
            + spacing * CGFloat(max(0, sizes.count - 1))
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
