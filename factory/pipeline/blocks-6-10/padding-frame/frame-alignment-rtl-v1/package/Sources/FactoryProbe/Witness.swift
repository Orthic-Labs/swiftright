import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.padding-frame, case frame-alignment-rtl: a small red view inside a fixed frame of every Alignment (blue is the 56x36
// reference), a child larger than its frame, and width-only / height-only frames. The same grid under a right-to-left layout direction: leading and trailing swap in frames, padding and stacks. The last row pads the swatch on one side.
func frameCell(_ alignment: Alignment) -> some View {
    Color.blue.frame(width: 56, height: 36).overlay {
        Color.red.frame(width: 16, height: 12).frame(width: 56, height: 36, alignment: alignment)
    }
}

struct Witness_frame_alignment_rtl: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { frameCell(.topLeading); frameCell(.top); frameCell(.topTrailing) }
            HStack(spacing: 6) { frameCell(.leading); frameCell(.center); frameCell(.trailing) }
            HStack(spacing: 6) { frameCell(.bottomLeading); frameCell(.bottom); frameCell(.bottomTrailing) }
            HStack(spacing: 6) {
                Color.blue.frame(width: 56, height: 36).overlay {
                    Color.red.frame(width: 70, height: 20).frame(width: 56, height: 36, alignment: .leading)
                }
                Color.blue.frame(width: 56, height: 36).overlay {
                    Color.red.frame(width: 70, height: 20).frame(width: 56, height: 36, alignment: .trailing)
                }
                Color.blue.frame(width: 56, height: 36).overlay {
                    Color.red.frame(width: 70, height: 50).frame(width: 56, height: 36, alignment: .bottomTrailing)
                }
            }
            HStack(spacing: 6) {
                Color.blue.frame(width: 56, height: 36).overlay { Color.red.padding(.leading, 12) }
                Color.blue.frame(width: 56, height: 36).overlay { Color.red.padding(.trailing, 20) }
                Color.blue.frame(width: 56, height: 36).overlay { Color.red.padding(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 4)) }
            }
        }
        .environment(\.layoutDirection, .rightToLeft).environment(\.colorScheme, .light)
    }
}
