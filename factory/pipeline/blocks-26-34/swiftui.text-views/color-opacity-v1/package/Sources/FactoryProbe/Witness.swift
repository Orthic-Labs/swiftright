#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tv_opacity: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.1)).frame(width: 60, height: 40)
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 60, height: 40)
                Rectangle().fill(Color.red.opacity(0.5)).frame(width: 60, height: 40)
                Rectangle().fill(Color.blue.opacity(0.5).opacity(0.5)).frame(width: 60, height: 40)
            }
            ZStack { Rectangle().fill(Color.blue).frame(width: 240, height: 40); Rectangle().fill(Color.white.opacity(0.5)).frame(width: 120, height: 40); Color.black.opacity(0.3).frame(width: 60, height: 40) }
            HStack(spacing: 0) {
                Rectangle().fill(Color(red: 1, green: 0.5, blue: 0).opacity(0.5)).frame(width: 80, height: 40)
                Color.green.opacity(0.25).frame(width: 80, height: 40)
                Color.red.opacity(0).frame(width: 80, height: 40)
            }
            Color.primary.opacity(0.1).frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
