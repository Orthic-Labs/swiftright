#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_vstack: View {
    var body: some View {
        VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 40, height: 40); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 40) }.frame(width: 40, height: 200)
    }
}
