#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_fixed: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer().frame(width: 30); Rectangle().fill(Color.blue).frame(width: 40, height: 20); Spacer() }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Spacer().frame(width: 20, height: 20); Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Spacer().frame(width: 20, height: 20) }.frame(width: 200, height: 20)
        }
    }
}
