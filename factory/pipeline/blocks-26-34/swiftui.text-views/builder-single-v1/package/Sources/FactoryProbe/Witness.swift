#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_tv_NoTrailing: View { var body: some View { Rectangle().fill(Color.red).frame(width: 20, height: 20) } }

struct Witness_tv_Header<Trailing: View>: View {
    let width: CGFloat
    let trailing: Trailing
    init(width: CGFloat, @ViewBuilder trailing: () -> Trailing) { self.width = width; self.trailing = trailing() }
    var body: some View {
        HStack(spacing: 0) { Rectangle().fill(Color.blue).frame(width: width, height: 20); Spacer(); trailing }.frame(width: 240, height: 20)
    }
}

extension Witness_tv_Header where Trailing == Witness_tv_NoTrailing {
    init(width: CGFloat) { self.init(width: width) { Witness_tv_NoTrailing() } }
}

struct Witness_tv_builder_single: View {
    var body: some View {
        VStack(spacing: 10) {
            Witness_tv_Header(width: 60)
            Witness_tv_Header(width: 100) { Rectangle().fill(Color.green).frame(width: 40, height: 20) }
            Witness_tv_Header(width: 30) { Rectangle().fill(Color.green).frame(width: 40, height: 20); Rectangle().fill(Color.red).frame(width: 10, height: 20) }
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
