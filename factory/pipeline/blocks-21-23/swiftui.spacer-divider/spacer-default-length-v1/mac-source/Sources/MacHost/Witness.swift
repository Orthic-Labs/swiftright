#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_default: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 100, height: 20)
            HStack { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 84, height: 20)
            HStack { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 80, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 80, height: 20)
            HStack { Rectangle().fill(Color.red).frame(width: 40, height: 20); Spacer(minLength: 0); Rectangle().fill(Color.blue).frame(width: 40, height: 20) }.frame(width: 80, height: 20)
            HStack { Rectangle().fill(Color.red).frame(width: 30, height: 20); Rectangle().fill(Color.blue).frame(width: 30, height: 20); Spacer(minLength: 0); Rectangle().fill(Color.green).frame(width: 30, height: 20) }.frame(width: 100, height: 20)
            VStack { Rectangle().fill(Color.red).frame(width: 20, height: 20); Spacer(); Rectangle().fill(Color.blue).frame(width: 20, height: 20) }.frame(width: 20, height: 44)
        }
    }
}
