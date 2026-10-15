#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ax_element: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Text("Memory").frame(width: 100, height: 20, alignment: .leading); Text("1.2 GB").frame(width: 100, height: 20, alignment: .leading) }.accessibilityElement(children: .combine)
            HStack(spacing: 0) { Text("Swap").frame(width: 100, height: 20, alignment: .leading); Text("0 MB").frame(width: 100, height: 20, alignment: .leading) }.accessibilityElement(children: .ignore).accessibilityLabel("Swap usage")
            HStack(spacing: 0) { Text("Disk").frame(width: 100, height: 20, alignment: .leading); Text("40 GB").frame(width: 100, height: 20, alignment: .leading) }.accessibilityElement(children: .contain)
            HStack(spacing: 0) { Text("CPU").frame(width: 100, height: 20, alignment: .leading); Text("12 %").frame(width: 100, height: 20, alignment: .leading) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
