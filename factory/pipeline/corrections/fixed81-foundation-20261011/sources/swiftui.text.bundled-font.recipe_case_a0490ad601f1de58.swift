#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_text_bundled_font: View {
    var body: some View {
        Text("SwiftRight AV")
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .lineLimit(2)
            .frame(width: 120, alignment: .leading)
    }
}
