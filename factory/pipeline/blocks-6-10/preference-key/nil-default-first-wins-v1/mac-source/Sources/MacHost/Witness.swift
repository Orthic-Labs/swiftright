#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
#endif

/// Optional-valued key without a defaultValue (nil through ExpressibleByNilLiteral); the first contribution wins.
struct WitnessFirstWidth: PreferenceKey {
    typealias Value = CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

struct WitnessWidthReader: View {
    let publishes: Bool
    let fill: Color
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if publishes {
                Rectangle().fill(Color.red).frame(width: 30, height: 8).preference(key: WitnessFirstWidth.self, value: 30)
                Rectangle().fill(Color.blue).frame(width: 80, height: 8).preference(key: WitnessFirstWidth.self, value: 80)
            }
            Rectangle().fill(fill).frame(width: width, height: 6)
        }
        .onPreferenceChange(WitnessFirstWidth.self) { width = $0 ?? 20 }    // 20 = the nil default's fallback
    }
}

struct Witness_preference_nil_default: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WitnessWidthReader(publishes: true, fill: .green)
            WitnessWidthReader(publishes: false, fill: .orange)
        }
        .environment(\.colorScheme, .light)
    }
}
