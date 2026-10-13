#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct WitnessMaxWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct WitnessSumWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

/// Children publish their widths upward; the parent renders the reduced values as bars (max of 30/70/60 = 70, sum = 160).
struct Witness_preference_key: View {
    @State private var maxWidth: CGFloat = 0
    @State private var sumWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color.red).frame(width: 30, height: 12)
                .preference(key: WitnessMaxWidth.self, value: 30).preference(key: WitnessSumWidth.self, value: 30)
            Rectangle().fill(Color.blue).frame(width: 70, height: 10)
                .preference(key: WitnessMaxWidth.self, value: 70).preference(key: WitnessSumWidth.self, value: 70)
            Rectangle().fill(Color.orange).frame(width: 60, height: 10)
                .preference(key: WitnessMaxWidth.self, value: 60).preference(key: WitnessSumWidth.self, value: 60)
            Rectangle().fill(Color.green).frame(width: maxWidth, height: 6)
            Rectangle().fill(Color.purple).frame(width: sumWidth, height: 6)
        }
        .onPreferenceChange(WitnessMaxWidth.self) { maxWidth = $0 }
        .onPreferenceChange(WitnessSumWidth.self) { sumWidth = $0 }
        .environment(\.colorScheme, .light)
    }
}
