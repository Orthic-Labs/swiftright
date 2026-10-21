#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #73, case basic-shapes-v1: font-sized circle, circle.fill, square, square.fill, checkmark.square and checkmark.square.fill (the shapes MarkdownUI's list bullets and task lists use) at 13 and 17 pt.
struct Witness_g73_basic_shapes_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Image(systemName: "circle").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.blue).frame(width: 40, height: 40); Image(systemName: "circle.fill").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40); Image(systemName: "square").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "square.fill").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40); Image(systemName: "checkmark.square").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.purple).frame(width: 40, height: 40); Image(systemName: "checkmark.square.fill").font(Font.system(size: 13, weight: .regular)).foregroundStyle(Color.gray).frame(width: 40, height: 40) }
            HStack(spacing: 0) { Image(systemName: "circle").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.blue).frame(width: 40, height: 40); Image(systemName: "circle.fill").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.red).frame(width: 40, height: 40); Image(systemName: "square").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.green).frame(width: 40, height: 40); Image(systemName: "square.fill").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.orange).frame(width: 40, height: 40); Image(systemName: "checkmark.square").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.purple).frame(width: 40, height: 40); Image(systemName: "checkmark.square.fill").font(Font.system(size: 17, weight: .regular)).foregroundStyle(Color.gray).frame(width: 40, height: 40) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
