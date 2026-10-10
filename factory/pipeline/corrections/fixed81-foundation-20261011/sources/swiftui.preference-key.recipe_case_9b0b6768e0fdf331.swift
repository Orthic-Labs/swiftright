#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

import Foundation

struct Witness_preference_key: View {
    var body: some View {
        VStack {
            ForEach(0..<3, id: \.self) { index in
                Text("\(index)").preference(key: WitnessWidths.self, value: CGFloat((index + 2) * 10))
            }
        }.onPreferenceChange(WitnessWidths.self) { _ in }
    }
}

struct WitnessWidths: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static let reductionMode = "max"
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if reductionMode == "sum" { value += next } else { value = max(value, next) }
    }
}
