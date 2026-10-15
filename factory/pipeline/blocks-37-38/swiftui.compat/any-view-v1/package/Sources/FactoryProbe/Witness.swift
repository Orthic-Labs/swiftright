#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_co_any: View {
    @State private var swap = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Swap") { swap.toggle() }.frame(width: 100, height: 28)
            // AnyView(EmptyView()) is a view with no content; AnyView of a changing concrete type
            AnyView(EmptyView()).frame(width: 40, height: 10)
            (swap ? AnyView(Color.green.frame(width: 40, height: 20)) : AnyView(Color.blue.frame(width: 60, height: 12)))
            Color.gray.frame(width: 80, height: 6)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
