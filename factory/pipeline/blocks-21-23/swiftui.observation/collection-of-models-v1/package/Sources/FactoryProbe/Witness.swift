#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

enum Box { nonisolated(unsafe) static var stamp = 0 }

func swatch(_ s: Int) -> Color {
    switch s % 6 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    case 4: return Color.orange
    case 5: return Color.purple
    default: return Color.gray
    }
}

@Observable final class Item { let id: Int; var done = false; init(_ id: Int) { self.id = id } }
@Observable final class Store { var items: [Item] = [Item(0), Item(1), Item(2)] }

struct ItemRow: View {
    let item: Item
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(item.done ? Color.green : Color.red).frame(width: 20, height: 20)
            Rectangle().fill(swatch(Box.stamp)).frame(width: 20, height: 20)
            Text("item \(item.id) done=\(item.done ? 1 : 0) s=\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading)
        }.frame(width: 240, height: 20)
    }
}

struct ItemList: View {
    let store: Store
    var body: some View {
        VStack(spacing: 0) { ForEach(store.items, id: \.id) { item in ItemRow(item: item) } }
    }
}

struct Witness_obs_collection: View {
    @State private var store = Store()
    var body: some View {
        VStack(spacing: 0) {
            ItemList(store: store).frame(width: 240, height: 100, alignment: .top)
            Button("Toggle 1") { Box.stamp += 1; store.items[1].done.toggle() }.frame(width: 240, height: 32)
            Button("Append") { Box.stamp += 1; store.items.append(Item(store.items.count)) }.frame(width: 240, height: 32)
            Button("Toggle 3") { Box.stamp += 1; store.items[3].done.toggle() }.frame(width: 240, height: 32)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}
