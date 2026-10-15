#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sym_styles: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Image(systemName: "gearshape").font(.callout).foregroundStyle(Color.blue).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.subheadline).foregroundStyle(Color.red).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.footnote).foregroundStyle(Color.green).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.caption).foregroundStyle(Color.orange).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.title3).foregroundStyle(Color.purple).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.title2).foregroundStyle(Color.gray).frame(width: 34, height: 34); Image(systemName: "gearshape").font(.title).foregroundStyle(Color.blue).frame(width: 34, height: 34) }
            HStack(spacing: 0) { Image(systemName: "doc").font(.callout).foregroundStyle(Color.red).frame(width: 34, height: 34); Image(systemName: "doc").font(.subheadline).foregroundStyle(Color.green).frame(width: 34, height: 34); Image(systemName: "doc").font(.footnote).foregroundStyle(Color.orange).frame(width: 34, height: 34); Image(systemName: "doc").font(.caption).foregroundStyle(Color.purple).frame(width: 34, height: 34); Image(systemName: "doc").font(.title3).foregroundStyle(Color.gray).frame(width: 34, height: 34); Image(systemName: "doc").font(.title2).foregroundStyle(Color.blue).frame(width: 34, height: 34); Image(systemName: "doc").font(.title).foregroundStyle(Color.red).frame(width: 34, height: 34) }
            HStack(spacing: 0) { Image(systemName: "sidebar.left").font(.callout).foregroundStyle(Color.green).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.subheadline).foregroundStyle(Color.orange).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.footnote).foregroundStyle(Color.purple).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.caption).foregroundStyle(Color.gray).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.title3).foregroundStyle(Color.blue).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.title2).foregroundStyle(Color.red).frame(width: 34, height: 34); Image(systemName: "sidebar.left").font(.title).foregroundStyle(Color.green).frame(width: 34, height: 34) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
