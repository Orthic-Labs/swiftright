#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #82, case lazy-vgrid-v1: LazyVGrid with fixed, flexible-limited and adaptive columns, centred in a 300 pt container (frames measured on macOS 27).
struct Witness_g82_lazy_vgrid_v1: View {
    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.fixed(60)), GridItem(.fixed(80))]) {
                ForEach(0..<4, id: \.self) { i in Color.blue.frame(height: 14 + CGFloat(i % 2) * 6) }
            }.frame(width: 300)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 4) {
                ForEach(0..<6, id: \.self) { _ in Color.green.frame(height: 16) }
            }.frame(width: 300)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 50, maximum: 80), spacing: 12), count: 3)) {
                ForEach(0..<3, id: \.self) { _ in Color.orange.frame(height: 16) }
            }.frame(width: 300)
        }
    }
}
