import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.pixel-ties, case layout: stacks with odd spacing, odd padding, frame alignment inside a frame whose spare room is an even
// number of points (centre offset = an odd number of points), all inside a 300 x 200 pt root at (10, 20) pt. Every length is a whole number
// of points, so edges alternate between exact half pixels and whole pixels, and nothing is laid out to avoid the half pixels.
func tieCell(_ w: CGFloat, _ h: CGFloat, _ inner: CGFloat, _ alignment: Alignment) -> some View {
    Color.blue.frame(width: w, height: h).overlay {
        Color.red.frame(width: inner, height: inner).frame(width: w, height: h, alignment: alignment)
    }
}

struct Witness_pixel_ties_layout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                tieCell(31, 21, 9, .center)
                tieCell(45, 21, 11, .topLeading)
                tieCell(27, 21, 5, .bottomTrailing)
                tieCell(61, 21, 15, .center)
            }
            HStack(spacing: 7) {
                Color.green.frame(width: 17, height: 13).padding(3)
                Color.orange.frame(width: 23, height: 13).padding(.horizontal, 5).padding(.vertical, 1)
                Color.purple.frame(width: 39, height: 13)
                Color.red.frame(width: 11, height: 13).padding(.leading, 9)
            }
            VStack(spacing: 1) {
                ForEach(0..<9, id: \.self) { i in
                    Color.blue.frame(width: CGFloat(2 * i + 3), height: 3)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { i in
                    Color.red.frame(width: 7, height: CGFloat(2 * i + 3))
                }
            }
            Color.green.frame(width: 33, height: 9).padding(.leading, 41).padding(.top, 3)
        }
        .padding(.leading, 5)
        .frame(width: 300, height: 200, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }
}
