#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_horizontal: View {
    var body: some View {
        VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 200, height: 40); Divider(); Rectangle().fill(Color.blue).frame(width: 200, height: 40) }.frame(width: 200)
    }
}
