#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif
import Observation

// Issue #60, case environment-model-v1: an @Observable model put in the environment with .environment(model) and read two levels down with
// @Environment(G60Model.self); the bars' widths and colour come only from the model.
@Observable final class G60Model {
    var widths: [CGFloat] = [140, 90, 40]
    var red = 0.8   // whole sRGB levels (204, 51, 102): CI 39625068738 differed by 1 level everywhere at 0.9 and 0.3
}

struct G60Bars: View {
    @Environment(G60Model.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<model.widths.count, id: \.self) { i in
                Rectangle().fill(Color(.sRGB, red: model.red, green: 0.2, blue: 0.4, opacity: 1)).frame(width: model.widths[i], height: 24)
            }
        }
    }
}

struct G60Middle: View { var body: some View { G60Bars().padding(10) } }

struct Witness_g60_environment_model_v1: View {
    @State private var model = G60Model()
    var body: some View { G60Middle().environment(model).frame(width: 200, height: 140, alignment: .topLeading) }
}
