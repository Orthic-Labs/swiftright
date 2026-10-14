#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_divider_colour: View {
    var body: some View {
        VStack(spacing: 10) {
            Divider().frame(width: 160)
            Divider().overlay { Color.red }.frame(width: 160)
            Divider().frame(width: 160, height: 12)
            HStack(spacing: 10) { Divider(); Divider().overlay { Color.red }; Divider().frame(width: 12) }.frame(height: 60)
        }
    }
}
