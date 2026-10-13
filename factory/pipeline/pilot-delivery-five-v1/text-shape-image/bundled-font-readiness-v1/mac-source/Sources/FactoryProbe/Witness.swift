import SwiftUI

/// Exact accepted bundled-font witness; host registration remains process-only.
struct Witness_tinos_bundled_text_pilot: View {
    var body: some View {
        Text("SwiftRight bundled Tinos font witness")
            .font(.custom("Tinos-Regular", size: 18))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 128, alignment: .leading)
    }
}
