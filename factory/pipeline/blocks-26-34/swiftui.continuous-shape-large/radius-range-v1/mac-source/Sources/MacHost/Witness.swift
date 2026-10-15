#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cl_range: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 13.1, style: .continuous).fill(Color.red).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.blue).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.green).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.purple).frame(width: 100, height: 30)
        }.frame(width: 240, height: 200)
    }
}
