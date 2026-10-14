#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_hstack: View {
    var body: some View {
        HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 40, height: 40); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 40) }.frame(width: 200, height: 40)
    }
}
