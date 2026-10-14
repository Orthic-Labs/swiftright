#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_ties: View {
    var body: some View {
        VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 100, height: 3); Divider(); Rectangle().fill(Color.blue).frame(width: 100, height: 5); Divider(); Rectangle().fill(Color.red).frame(width: 100, height: 7); Divider(); Rectangle().fill(Color.blue).frame(width: 100, height: 9); Divider() }.frame(width: 100)
    }
}
