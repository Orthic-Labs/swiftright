#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #54, case tint-controls-v1: .tint(.red) on a prominent Button (empty label: its glyphs are not part of this case), a switch and a checkbox in the on state,
// a Slider and a ProgressView. The artwork was measured with the accent only: the tint replaces the accent, keeping the measured mix toward white or black.
struct Witness_e54_tint_controls_v1: View {
    var body: some View {
        VStack(spacing: 14) {
            Button(action: {}) { Color.clear.frame(width: 50, height: 14) }.buttonStyle(.borderedProminent)
            HStack(spacing: 20) {
                Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
                Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.checkbox)
            }
            Slider(value: .constant(0.6), in: 0...1).frame(width: 140)
            ProgressView(value: 0.5).frame(width: 140)
        }
        .tint(.red)
        .frame(width: 240, height: 160)
    }
}
