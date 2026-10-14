#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_flexible: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { Spacer(); Rectangle().fill(Color.red).frame(width: 30, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 30, height: 20); Spacer(); Rectangle().fill(Color.green).frame(width: 30, height: 20); Spacer() }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 30, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 30, height: 20); Spacer(minLength: 40); Rectangle().fill(Color.green).frame(width: 30, height: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Spacer(); Rectangle().fill(Color.red).frame(width: 30, height: 20) }.frame(width: 200, height: 20)
        }
    }
}
