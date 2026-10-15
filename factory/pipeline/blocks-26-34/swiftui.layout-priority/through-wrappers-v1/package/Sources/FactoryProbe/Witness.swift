#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lp_Wrapped: View {
    var body: some View { Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1) }
}

struct Witness_lp_through_wrappers: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).padding(4).layoutPriority(1) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Witness_lp_Wrapped() }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); ZStack { Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20) }.layoutPriority(1) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1).padding(4); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1).opacity(0.99) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1).frame(maxWidth: .infinity) }.frame(width: 200, height: 20)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20); Rectangle().fill(Color.blue).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20).layoutPriority(1).onAppear {} }.frame(width: 200, height: 20)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
