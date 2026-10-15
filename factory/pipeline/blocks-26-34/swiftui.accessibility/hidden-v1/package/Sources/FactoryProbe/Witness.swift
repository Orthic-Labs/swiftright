#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ax_hidden: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Visible one").frame(width: 240, height: 20, alignment: .leading)
            Text("Hidden text").accessibilityHidden(true).frame(width: 240, height: 20, alignment: .leading)
            Button("Hidden button") { }.accessibilityHidden(true).frame(width: 240, height: 32)
            VStack(spacing: 0) { Text("inner a").frame(width: 240, height: 20, alignment: .leading); Text("inner b").frame(width: 240, height: 20, alignment: .leading) }.accessibilityHidden(true)
            Text("Visible two").frame(width: 240, height: 20, alignment: .leading)
            Text("Shown again").accessibilityHidden(false).frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
