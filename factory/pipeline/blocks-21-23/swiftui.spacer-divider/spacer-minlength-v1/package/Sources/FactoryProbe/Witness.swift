#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_minlength: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 60, height: 20); Spacer(minLength: 50); Rectangle().fill(Color.blue).frame(width: 60, height: 20) }.frame(width: 150, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 60, height: 20); Spacer(minLength: 10); Rectangle().fill(Color.blue).frame(width: 60, height: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 60, height: 20); Spacer(minLength: 100); Rectangle().fill(Color.blue).frame(width: 60, height: 20) }.frame(width: 200, height: 20)
        }
    }
}
