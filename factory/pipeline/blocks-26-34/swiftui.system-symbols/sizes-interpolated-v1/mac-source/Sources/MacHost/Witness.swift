#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sym_interp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Image(systemName: "gearshape").font(Font.system(size: 19, weight: .regular)).foregroundStyle(Color.blue).frame(width: 40, height: 40); Image(systemName: "gearshape").font(Font.system(size: 21, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40); Image(systemName: "gearshape").font(Font.system(size: 25, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "gearshape").font(Font.system(size: 27, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40) }
            HStack(spacing: 0) { Image(systemName: "doc").font(Font.system(size: 19, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40); Image(systemName: "doc").font(Font.system(size: 21, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "doc").font(Font.system(size: 25, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40); Image(systemName: "doc").font(Font.system(size: 27, weight: .regular)).foregroundStyle(Color.purple).frame(width: 40, height: 40) }
            HStack(spacing: 0) { Image(systemName: "sidebar.left").font(Font.system(size: 19, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "sidebar.left").font(Font.system(size: 21, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40); Image(systemName: "sidebar.left").font(Font.system(size: 25, weight: .regular)).foregroundStyle(Color.purple).frame(width: 40, height: 40); Image(systemName: "sidebar.left").font(Font.system(size: 27, weight: .regular)).foregroundStyle(Color.gray).frame(width: 40, height: 40) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
