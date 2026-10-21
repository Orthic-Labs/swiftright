#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_uia_b: View {
    @State private var sel: Int? = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) { Image(systemName: "star.fill").frame(width: 16, height: 16); Text("Star") }
            Image(systemName: "gear").frame(width: 16, height: 16).accessibilityLabel("Settings")
            Text("Hidden").accessibilityHidden(true)
            Slider(value: .constant(0.5), in: 0...1) { Text("Level") }
            List(selection: $sel) { Text("One").tag(1); Text("Two").tag(2); Text("Three").tag(3) }.frame(width: 180, height: 90)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
