import Foundation
#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Block swiftui.padding-frame, case flexible-frame: frame(min/max Width/Height) against a fixed blue row. The red view is
// inside the overlay, so it is offered the row size; rows differ in the offer (200, 100, 60) and the bounds.
func flexRow<Inner: View>(_ width: CGFloat, _ inner: Inner) -> some View {
    Color.blue.frame(width: width, height: 20).overlay(alignment: .leading) { inner }
}

struct Witness_flexible_frame: View {
    var body: some View {
        VStack(spacing: 4) {
            flexRow(200, Color.red.frame(maxWidth: .infinity, maxHeight: .infinity))
            flexRow(200, Color.red.frame(minWidth: 80, maxWidth: 120, minHeight: 10, maxHeight: 16))
            flexRow(100, Color.red.frame(minWidth: 80, maxWidth: 120, minHeight: 10, maxHeight: 16))
            flexRow(60, Color.red.frame(minWidth: 80, maxWidth: 120, minHeight: 10, maxHeight: 16))
            flexRow(200, Color.red.frame(maxWidth: 50))
            flexRow(200, Color.red.frame(width: 40, height: 12).frame(maxWidth: .infinity, alignment: .trailing))
            flexRow(200, Color.red.frame(width: 300, height: 12).frame(maxWidth: 100))
            flexRow(200, Color.red.frame(width: 30, height: 8).frame(minWidth: 70, minHeight: 14, alignment: .trailing))
            HStack(spacing: 0) {
                Color.red.frame(minWidth: 20, maxWidth: .infinity)
                Color.green.frame(width: 40, height: 20)
                Color.red.frame(minWidth: 30, maxWidth: .infinity)
                Color.orange.frame(width: 20, height: 20)
            }.frame(width: 200, height: 20)
        }
        .environment(\.colorScheme, .light)
    }
}
