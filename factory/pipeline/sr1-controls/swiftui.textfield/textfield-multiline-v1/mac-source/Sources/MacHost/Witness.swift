#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #60 pass 3, case textfield-multiline-v1: `TextField(axis: .vertical)` grows one line at a time up to the `lineLimit`. The bezel heights 56 / 40 / 24 pt follow from the one-line
// field (8 pt of cell inset + 16 pt per line); this case measures them. The text and the placeholder are excluded from the pixel gate (Segoe UI against SF).
struct Witness_p60_textfield_multiline_v1: View {
    @State private var notes = "line one\nline two\nline three"
    @State private var empty = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Notes", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 160)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2).textFieldStyle(.roundedBorder).frame(width: 160)
            TextField("Empty", text: $empty, axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 160)
        }
        .frame(width: 240, height: 200)
    }
}
