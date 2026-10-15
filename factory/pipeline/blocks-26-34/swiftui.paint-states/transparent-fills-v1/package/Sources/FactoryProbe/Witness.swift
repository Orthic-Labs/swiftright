#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ps_transparent: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(width: 300, height: 26)
                ZStack { Rectangle().fill(Color.blue).frame(width: 300, height: 26); Color.clear.frame(width: 300, height: 26) }
                ZStack { Rectangle().fill(Color.green).frame(width: 300, height: 26); Rectangle().fill(Color.black.opacity(0.001)).frame(width: 300, height: 26) }
                ZStack { Rectangle().fill(Color.orange).frame(width: 300, height: 26); Color.red.opacity(0).frame(width: 300, height: 26) }
                ZStack { Rectangle().fill(Color.purple).frame(width: 300, height: 26); Rectangle().fill(Color.clear).frame(width: 150, height: 26) }
                ZStack { Rectangle().fill(Color.gray).frame(width: 300, height: 26); Color.black.opacity(0.01).frame(width: 300, height: 26) }
                Button { } label: { ZStack { Color.black.opacity(0.001); Rectangle().fill(Color.pink).frame(width: 40, height: 20) }.frame(width: 300, height: 26) }.buttonStyle(.plain)
                Color.clear.frame(width: 300, height: 26)
            }.padding(10)
        }
        .frame(width: 320, height: 240)
    }
}
