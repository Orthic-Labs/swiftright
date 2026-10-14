#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_spacing: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 80, height: 20)
            HStack(spacing: 20) { Rectangle().fill(Color.red).frame(width: 30, height: 20); Rectangle().fill(Color.blue).frame(width: 30, height: 20); Spacer(); Rectangle().fill(Color.green).frame(width: 30, height: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 20) { Rectangle().fill(Color.red).frame(width: 30, height: 20); Spacer(minLength: 0); Rectangle().fill(Color.blue).frame(width: 30, height: 20); Spacer(minLength: 0); Rectangle().fill(Color.green).frame(width: 30, height: 20) }.frame(width: 100, height: 20)
            HStack(spacing: 4) { Rectangle().fill(Color.red).frame(width: 30, height: 20); Spacer(minLength: 0); Rectangle().fill(Color.blue).frame(width: 30, height: 20) }.frame(width: 60, height: 20)
        }
    }
}
