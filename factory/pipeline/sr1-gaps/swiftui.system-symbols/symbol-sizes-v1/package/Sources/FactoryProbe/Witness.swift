#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #63, case symbol-sizes-v1: font-sized Image(systemName:) star.fill at 9, 13, 16, 18, 24, 28, 30, 32 pt (table sizes not covered by blocks-26-34 sizes-v1, which uses 10-22).
struct Witness_g63_symbol_sizes_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Image(systemName: "star.fill").font(Font.system(size: 9, weight: .regular)).foregroundStyle(Color.blue).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 16, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 18, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40) }
            HStack(spacing: 0) { Image(systemName: "star.fill").font(Font.system(size: 24, weight: .regular)).foregroundStyle(Color.purple).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 28, weight: .regular)).foregroundStyle(Color.gray).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 30, weight: .regular)).foregroundStyle(Color.blue).frame(width: 40, height: 40); Image(systemName: "star.fill").font(Font.system(size: 32, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
