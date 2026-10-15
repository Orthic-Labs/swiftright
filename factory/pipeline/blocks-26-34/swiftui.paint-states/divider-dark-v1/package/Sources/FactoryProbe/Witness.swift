#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ps_divider_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(spacing: 10) {
                Divider().frame(width: 200)
                ZStack { Rectangle().fill(Color.blue).frame(width: 200, height: 40); Divider() }.frame(width: 200, height: 40)
                ZStack { Color.white.frame(width: 200, height: 40); Divider() }.frame(width: 200, height: 40)
                HStack(spacing: 10) { Rectangle().fill(Color.red).frame(width: 60, height: 40); Divider(); Rectangle().fill(Color.green).frame(width: 60, height: 40) }.frame(height: 40)
            }.padding(10)
        }
        .frame(width: 320, height: 240).environment(\.colorScheme, .dark)
    }
}
