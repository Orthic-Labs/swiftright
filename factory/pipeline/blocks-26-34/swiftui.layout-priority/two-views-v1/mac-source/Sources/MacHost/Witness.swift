#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lp_two_views: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(-1); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20) }.frame(width: 200, height: 20)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
