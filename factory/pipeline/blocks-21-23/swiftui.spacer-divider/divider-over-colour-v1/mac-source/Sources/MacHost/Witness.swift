#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_over: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack { Rectangle().fill(Color.blue).frame(width: 100, height: 40); Divider() }.frame(width: 100, height: 40)
            ZStack { Color.black.frame(width: 100, height: 40); Divider() }.frame(width: 100, height: 40)
        }
    }
}
