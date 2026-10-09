@_spi(Backends) import SwiftCrossUI

/// One node of the committed (resolved) tree, as the sink saw it.
public struct SinkNode {
    public let widget: DummyBackend.Widget
    public let kind: String
    public var text: String?
    public var size: SIMD2<Int>
    public var position: SIMD2<Int>
    public var focused: Bool
    public var children: [SinkNode]

    public var id: ObjectIdentifier { ObjectIdentifier(widget) }

    public func find(kind: String) -> [SinkNode] {
        var out: [SinkNode] = []
        if self.kind == kind { out.append(self) }
        for child in children { out += child.find(kind: kind) }
        return out
    }

    public func contains(_ widget: DummyBackend.Widget) -> Bool {
        self.widget === widget || children.contains { $0.contains(widget) }
    }

    public var all: [SinkNode] { [self] + children.flatMap(\.all) }
}

extension DummyBackend {
    /// Resolved tree under `window`'s content container.
    public func tree(of window: Window) -> SinkNode? {
        guard let content = window.content else { return nil }
        return node(for: content, position: .zero)
    }

    func node(for widget: Widget, position: SIMD2<Int>) -> SinkNode {
        var text: String?
        var children: [(Widget, SIMD2<Int>)] = []
        if let t = widget as? TextView { text = t.content }
        if let t = widget as? TextField { text = t.value }
        if let c = widget as? Container {
            children = c.children.map { ($0.widget, $0.position) }
        } else if let b = widget as? Button, let label = b.label {
            children = [(label, .zero)]
        } else {
            children = widget.getChildren().map { ($0, .zero) }
        }
        return SinkNode(
            widget: widget,
            kind: widget.tag ?? "?",
            text: text,
            size: widget.size,
            position: position,
            focused: focusedWidget === widget,
            children: children.map { node(for: $0.0, position: $0.1) }
        )
    }
}
