import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.padding-frame, case padding-edges: padding on all edges, per-edge, Edge.Set, EdgeInsets, the default amount and
// fractional lengths. The blue base is 56x36; the red view inside the overlay is inset by the padding under test.
func padSwatch<Inner: View>(_ inner: Inner) -> some View {
    Color.blue.frame(width: 56, height: 36).overlay { inner }
}

struct Witness_padding_edges: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                padSwatch(Color.red.padding(8))
                padSwatch(Color.red.padding(.horizontal, 14))
                padSwatch(Color.red.padding(.vertical, 6))
                padSwatch(Color.red.padding(.top, 10))
            }
            HStack(spacing: 8) {
                padSwatch(Color.red.padding(.leading, 12).padding(.bottom, 4))
                padSwatch(Color.red.padding(EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 4)))
                padSwatch(Color.red.padding())
                padSwatch(Color.red.padding(.trailing, 20))
            }
            HStack(spacing: 8) {
                padSwatch(Color.red.padding(.all, 3.3))
                padSwatch(Color.red.padding([.top, .leading], 9.5))
                padSwatch(Color.red.padding(EdgeInsets(top: 1.25, leading: 7.75, bottom: 0, trailing: 2.5)))
            }
            // padding grows the padded view, so it moves the siblings that follow it
            HStack(spacing: 0) {
                Color.green.frame(width: 20, height: 20).padding(.trailing, 10)
                Color.red.frame(width: 20, height: 20).padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                Color.green.frame(width: 20, height: 20).padding(.horizontal, 4).padding(.vertical, 2)
                Color.red.frame(width: 15.5, height: 11.25).padding(3.3)
                Color.blue.frame(width: 12, height: 12)
            }
        }
        .environment(\.colorScheme, .light)
    }
}
