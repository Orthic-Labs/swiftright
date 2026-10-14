#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_spacing: View {
    var body: some View {
        VStack { Rectangle().fill(Color.red).frame(width: 200, height: 30); Divider(); Rectangle().fill(Color.blue).frame(width: 200, height: 30) }.frame(width: 200)
    }
}
