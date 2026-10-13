import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.padding-frame, case nested-fractional: nested fixed frames, padding and stacks with fractional sizes, so edges land
// between device pixels (scale 2.5: 0.4 pt steps) and SwiftUI's snapping decides every edge. Colors and Rectangle both appear.
func fracCell(width: CGFloat, height: CGFloat, w: CGFloat, h: CGFloat, _ alignment: Alignment) -> some View {
    Color.blue.frame(width: width, height: height).overlay {
        Rectangle().fill(Color.red).frame(width: w, height: h).frame(width: width, height: height, alignment: alignment)
    }
}

struct Witness_nested_fractional: View {
    var body: some View {
        VStack(spacing: 5.3) {
            HStack(spacing: 3.7) {
                fracCell(width: 90.5, height: 50.25, w: 33.3, h: 21.7, .bottomTrailing)
                fracCell(width: 61.1, height: 50.25, w: 20.45, h: 12.9, .center)
                fracCell(width: 40.65, height: 50.25, w: 9.15, h: 30.35, .topLeading)
            }
            HStack(spacing: 2.4) {
                Color.blue.frame(width: 30.3, height: 25.2).overlay {
                    Rectangle().fill(Color.green).frame(width: 20.4, height: 11.1).padding(2.35).frame(width: 30.3, height: 25.2, alignment: .topLeading)
                }
                Color.blue.frame(width: 17.7, height: 25.2)
                Color.red.frame(width: 21.9, height: 25.2)
                Color.blue.frame(width: 33.35, height: 25.2).overlay {
                    Color.orange.padding(.horizontal, 4.45).padding(.vertical, 6.15)
                }
                Rectangle().fill(Color.green).frame(width: 12.55, height: 25.2)
            }
            HStack(spacing: 0.9) {
                Rectangle().fill(Color.red).frame(width: 18.8, height: 9.4)
                Rectangle().fill(Color.red).frame(width: 18.8, height: 9.4)
                Rectangle().fill(Color.red).frame(width: 18.8, height: 9.4)
                Rectangle().fill(Color.red).frame(width: 18.8, height: 9.4)
            }
        }
        .environment(\.colorScheme, .light)
    }
}
