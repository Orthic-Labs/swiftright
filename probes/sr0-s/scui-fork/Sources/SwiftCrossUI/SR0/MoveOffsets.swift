import Foundation

// SR0-OVERRIDE O1 (additive API gap): SwiftUI's `MutableCollection.move(fromOffsets:toOffset:)`.
// SwiftCrossUI has no equivalent; the SR0 slice inventory requires it (CONTRACT section 2, Lists).
#if !SCUI_STOCK_MOVE
extension MutableCollection where Self: RandomAccessCollection {
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = Array(self)
        let moving = source.map { items[$0] }
        var target = destination
        for index in source.reversed() {
            items.remove(at: index)
            if index < target { target -= 1 }
        }
        items.insert(contentsOf: moving, at: target)
        for (offset, element) in items.enumerated() {
            self[self.index(startIndex, offsetBy: offset)] = element
        }
    }
}
#endif
