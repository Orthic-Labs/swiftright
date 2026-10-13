#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

/// Exact accepted Tinos witness; custom family remains observational until renderer proof.
struct Witness_tinos_bundled_text_pilot: View {
    var body: some View {
        Text("SwiftRight bundled Tinos font witness")
            .font(.custom("Tinos-Regular", size: 18))
            .lineLimit(1)
            .frame(width: 128, alignment: .leading)
    }
}
