#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_tv_Chip: ViewModifier {
    let ground: Color
    let inset: CGFloat
    func body(content: Content) -> some View {
        ZStack { Rectangle().fill(ground).frame(width: 64, height: 40); content.padding(inset) }
    }
}

struct Witness_tv_Maybe: ViewModifier {
    let on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.opacity(0.5) } else { content }
    }
}

struct Witness_tv_modifier: View {
    var body: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Color.red).frame(width: 40, height: 20).modifier(Witness_tv_Chip(ground: Color.blue, inset: 8))
            Rectangle().fill(Color.green).frame(width: 40, height: 20).modifier(Witness_tv_Maybe(on: true)).modifier(Witness_tv_Chip(ground: Color.red, inset: 4))
            Rectangle().fill(Color.green).frame(width: 40, height: 20).modifier(Witness_tv_Maybe(on: false))
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
