#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_swiftui_text_layout_baseline: View {
    var body: some View {
        Text("Aa")
            .font(.system(size: 24, weight: .regular, design: .default))
            .foregroundColor(Color.primary)
            .frame(width: 120, height: 48, alignment: .center)
            .environment(\.colorScheme, .light)
    }
}
