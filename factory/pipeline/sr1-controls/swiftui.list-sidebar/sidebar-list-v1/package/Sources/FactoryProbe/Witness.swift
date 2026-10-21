#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #60 pass 3, case sidebar-list-v1: `.listStyle(.sidebar)`: the grey ground, 32 pt rows, the rounded selection (row 2) and no separators. The row insets, the ground and the
// selection colours are ESTIMATES (E13 measured only the ground 229, the 32 pt rows and the rounded selection); this case is what measures them.
struct Witness_p60_sidebar_list_v1: View {
    @State private var selection: Int? = 2
    var body: some View {
        List(selection: $selection) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.listStyle(.sidebar).frame(width: 200, height: 160)
    }
}
