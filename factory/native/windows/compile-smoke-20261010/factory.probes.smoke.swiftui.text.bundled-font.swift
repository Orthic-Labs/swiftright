#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_text_bundled_font: View {
    var body: some View {
        Text("SwiftRight AV")
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .lineLimit(2)
            .frame(width: 80, alignment: .leading)
    }
}
