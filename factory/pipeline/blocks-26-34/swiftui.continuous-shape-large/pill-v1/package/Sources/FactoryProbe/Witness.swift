#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cl_pill: View {
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.red).frame(width: 200, height: 40)
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.blue).frame(width: 200, height: 24)
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.green).frame(width: 200, height: 10)
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.orange).frame(width: 60, height: 60)
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.purple).frame(width: 120, height: 6)
        }.frame(width: 240, height: 200)
    }
}
