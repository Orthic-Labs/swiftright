#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_vertical: View {
    var body: some View {
        HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 60, height: 80); Divider(); Rectangle().fill(Color.blue).frame(width: 60, height: 80) }.frame(height: 80)
    }
}
