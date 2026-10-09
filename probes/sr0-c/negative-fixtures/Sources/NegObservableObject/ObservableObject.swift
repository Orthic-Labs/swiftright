// SR0 negative fixture: `ObservableObject` and `@StateObject` are outside the SR0 slice (CONTRACT §2).
// The slice uses stdlib `@Observable` only. Expected: FAIL with "cannot find type 'ObservableObject' in scope".
import SwiftRightRuntime

final class CounterModel: ObservableObject {
    @Published var count = 0
}

struct ObservableObjectScreen: View {
    @StateObject private var model = CounterModel()
    var body: some View {
        Text("count")
    }
}
