#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif
import Combine

// Issue #88, case observable-object-v1: Combine-era state written as on the Mac. A @StateObject model with @Published properties, a child with @ObservedObject,
// a reader with @EnvironmentObject, a derived property fed by combineLatest + assign(to:), and a tap that changes the model.
final class G88Model: ObservableObject {
    @Published var taps = 0
    @Published var wide = false
    @Published var width: CGFloat = 60
    init() { $taps.combineLatest($wide).map { taps, wide in CGFloat(60 + taps * 20 + (wide ? 40 : 0)) }.assign(to: &$width) }
}

struct G88Bar: View {
    @ObservedObject var model: G88Model
    var body: some View { Rectangle().fill(model.taps % 2 == 0 ? Color.blue : Color.orange).frame(width: model.width, height: 30) }
}

struct G88Badge: View {
    @EnvironmentObject var model: G88Model
    var body: some View { Rectangle().fill(model.wide ? Color.red : Color.green).frame(width: 30, height: 30) }
}

struct G88Root: View {
    @StateObject private var model = G88Model()
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            G88Bar(model: model).offset(x: 40, y: 40)
            G88Badge().offset(x: 40, y: 100)
            Rectangle().fill(Color.gray).frame(width: 60, height: 40).offset(x: 40, y: 160).onTapGesture { model.taps += 1; if model.taps == 2 { model.wide = true } }
        }
        .frame(width: 320, height: 240)
        .environmentObject(model)
    }
}

struct Witness_g88_observable_object_v1: View {
    var body: some View { G88Root() }
}
