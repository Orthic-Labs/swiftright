#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cl_zero: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.blue).frame(width: 0, height: 8); RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.red).frame(width: 20, height: 8); RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.green).frame(width: 0, height: 8); RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.orange).frame(width: 20, height: 8) }
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.purple).frame(width: 100, height: 0)
            RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.blue).frame(width: 100, height: 10)
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.blue).frame(width: 0, height: 0)
        }.frame(width: 240, height: 200)
    }
}
