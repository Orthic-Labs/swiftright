#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tv_clear: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 120, height: 40); Rectangle().fill(Color.blue).frame(width: 120, height: 40); Rectangle().fill(Color.green).frame(width: 120, height: 40) }
            Color.clear.frame(width: 120, height: 120)
            Rectangle().fill(Color.clear).frame(width: 60, height: 50)
            Rectangle().fill(Color.red).frame(width: 30, height: 20).overlay { Color.clear }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
