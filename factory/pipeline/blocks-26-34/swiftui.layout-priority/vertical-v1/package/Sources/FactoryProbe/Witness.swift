#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lp_vertical: View {
    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150); Rectangle().fill(Color.blue).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150).layoutPriority(1) }.frame(width: 40, height: 120)
            VStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150).layoutPriority(1); Rectangle().fill(Color.blue).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150) }.frame(width: 40, height: 120)
            VStack(spacing: 4) { Rectangle().fill(Color.red).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150); Rectangle().fill(Color.blue).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150); Rectangle().fill(Color.green).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150).layoutPriority(2) }.frame(width: 40, height: 160)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
