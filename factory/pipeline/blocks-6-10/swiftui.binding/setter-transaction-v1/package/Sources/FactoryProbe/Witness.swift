#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_binding_transaction: View {
    // Each square is one observation from the binding setter: green = true. Row 1: the setter saw an animation; row 2: it saw disablesAnimations.
    static func facts() -> [[Bool]] {
        var seen: [Transaction] = []
        let b = Binding<Int>(get: { 0 }, set: { _, t in seen.append(t) })
        b.wrappedValue = 1
        var t = Transaction(animation: .linear(duration: 0.1)); t.disablesAnimations = true
        b.transaction(t).wrappedValue = 2
        b.animation(.easeIn(duration: 0.2)).wrappedValue = 3
        b.animation().wrappedValue = 4
        b.transaction(Transaction(animation: .linear(duration: 0.1))).transaction(Transaction()).wrappedValue = 5
        let constant = Binding.constant(7)
        constant.wrappedValue = 9
        return [seen.map { $0.animation != nil } + [constant.wrappedValue == 7], seen.map { $0.disablesAnimations } + [seen.count == 5]]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { column in
                        Rectangle().fill(Self.facts()[row][column] ? Color.green : Color.red).frame(width: 20, height: 20)
                    }
                }
            }
        }
    }
}
