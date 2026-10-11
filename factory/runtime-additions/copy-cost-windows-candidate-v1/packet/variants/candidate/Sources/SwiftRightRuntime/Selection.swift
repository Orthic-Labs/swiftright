import Foundation

// List selection (single and multiple), keyboard-driven selection hooks, and `onDelete`.
// https://developer.apple.com/documentation/swiftui/list/init(selection:content:)
// https://developer.apple.com/documentation/swiftui/view/tag(_:)
// https://developer.apple.com/documentation/swiftui/dynamicviewcontent/ondelete(perform:)
//
// Rows select through `.tag(_:)`. A row without a tag is not selectable. Selection writes go to the caller's
// binding; the runtime reads them back at each commit, so the selected flag always matches the binding.

/// Type-erased access to a List's selection binding.
@MainActor
struct SelectionAccess {
    let multiple: Bool
    let current: () -> Set<AnyHashable>
    let write: (Set<AnyHashable>) -> Void
}

@MainActor
protocol SelectionProviding {
    var selectionAccess: SelectionAccess? { get }
}

extension List: @MainActor SelectionProviding {}

extension List where SelectionValue: Hashable {
    /// Single selection. Apple: https://developer.apple.com/documentation/swiftui/list/init(selection:content:)
    public init(selection: Binding<SelectionValue?>, @ViewBuilder content: () -> Content) {
        let binding = selection
        self.init(content: content(), selectionAccess: SelectionAccess(
            multiple: false,
            current: { binding.wrappedValue.map { Set([AnyHashable($0)]) } ?? [] },
            write: { set in binding.wrappedValue = set.first?.base as? SelectionValue }
        ))
    }

    /// Multiple selection. Apple: https://developer.apple.com/documentation/swiftui/list/init(selection:content:)
    public init(selection: Binding<Set<SelectionValue>>, @ViewBuilder content: () -> Content) {
        let binding = selection
        self.init(content: content(), selectionAccess: SelectionAccess(
            multiple: true,
            current: { Set(binding.wrappedValue.map { AnyHashable($0) }) },
            write: { set in binding.wrappedValue = Set(set.compactMap { $0.base as? SelectionValue }) }
        ))
    }
}

/// Keyboard navigation over a List's tagged rows.
public enum ListNavigation: Sendable {
    case up
    case down
    /// Multiple selection only.
    case selectAll
}

// MARK: - onDelete

/// Holds one `onDelete` handler. Rows of the same handler share the box, so deletion can group them.
final class DeletionBox {
    let perform: (IndexSet) -> Void

    init(perform: @escaping (IndexSet) -> Void) { self.perform = perform }
}

/// The deletion a row belongs to, and the row's offset inside its ForEach as of the last evaluation.
struct DeletionHook {
    let box: DeletionBox
    let offset: Int
}

/// Wraps each row of the content with its deletion hook. The ForEach keyed segment stays on the wrapper.
struct OnDeleteContent<Content: DynamicViewContent>: DynamicViewContent, ViewContainer {
    let content: Content
    let box: DeletionBox

    @MainActor public var body: Never { return fatalError("OnDeleteContent has no body") }

    @MainActor
    func parts() -> [(Segment, any View)] {
        let rows = (content as? ViewContainer)?.parts() ?? []
        return rows.enumerated().map { offset, part in
            (part.0, ModifierWrapper(inner: part.1, spec: .deletion(DeletionHook(box: box, offset: offset))) as any View)
        }
    }
}

extension DynamicViewContent {
    /// Handler for rows deleted by the runtime (`Graph.deleteRows`, `Graph.deleteSelection`). The IndexSet holds the
    /// rows' offsets in this ForEach as of the last flush.
    /// Apple: https://developer.apple.com/documentation/swiftui/dynamicviewcontent/ondelete(perform:)
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some DynamicViewContent {
        OnDeleteContent(content: self, box: DeletionBox(perform: action ?? { _ in }))
    }
}

// MARK: - Graph hooks

extension Graph {
    /// Moves the List's cursor over its tagged rows. Up and down select one row; with `extending` in a multiple
    /// selection, the selection grows from the anchor to the new cursor. `selectAll` needs multiple selection.
    /// Returns false when the list has no selection, no tagged rows, or the move does not apply.
    @discardableResult
    public func navigateList(_ listID: String, _ move: ListNavigation, extending: Bool = false) -> Bool {
        guard let list = node(listID), let access = list.selection else { return false }
        let tags = taggedRows(of: list).map(\.tag)
        guard !tags.isEmpty else { return false }
        let current = access.current()
        switch move {
        case .selectAll:
            guard access.multiple else { return false }
            access.write(Set(tags))
            list.selectionAnchor = tags[0]
            list.selectionCursor = tags[tags.count - 1]
            return true
        case .up, .down:
            let cursor = list.selectionCursor.flatMap { tags.firstIndex(of: $0) }
                ?? tags.indices.first { current.contains(tags[$0]) }
            let target: Int
            if let cursor {
                target = move == .down ? min(cursor + 1, tags.count - 1) : max(cursor - 1, 0)
            } else {
                target = move == .down ? 0 : tags.count - 1
            }
            if extending, access.multiple,
               let anchor = list.selectionAnchor.flatMap({ tags.firstIndex(of: $0) }) {
                let range = min(anchor, target)...max(anchor, target)
                access.write(Set(range.map { tags[$0] }))
            } else {
                access.write([tags[target]])
                list.selectionAnchor = tags[target]
            }
            list.selectionCursor = tags[target]
            return true
        }
    }

    /// Selects a row by click, with the platform's modifiers. Single selection replaces. Multiple selection
    /// replaces, toggles with `.command`, or extends from the anchor with `.shift`. Returns false for an
    /// untagged row or a row with no selection owner.
    @discardableResult
    public func selectRow(_ rowID: String, modifiers: EventModifiers = []) -> Bool {
        guard let row = node(rowID), let tag = tagOf(row), let list = selectionOwner(of: row),
              let access = list.selection else { return false }
        var next: Set<AnyHashable>
        if access.multiple, modifiers.contains(.shift), let anchor = list.selectionAnchor {
            let tags = taggedRows(of: list).map(\.tag)
            guard let from = tags.firstIndex(of: anchor), let to = tags.firstIndex(of: tag) else { return false }
            next = Set(tags[min(from, to)...max(from, to)])
        } else if access.multiple, modifiers.contains(.command) {
            next = access.current()
            if next.contains(tag) { next.remove(tag) } else { next.insert(tag) }
            list.selectionAnchor = tag
        } else {
            next = [tag]
            list.selectionAnchor = tag
        }
        list.selectionCursor = tag
        access.write(next)
        return true
    }

    /// Deletes the named rows through their `onDelete` handlers. Rows are grouped by handler and each handler
    /// runs once with its offsets. Returns false when no named row has a handler.
    @discardableResult
    public func deleteRows(_ rowIDs: [String]) -> Bool {
        var order: [DeletionBox] = []
        var offsets: [ObjectIdentifier: [Int]] = [:]
        for id in rowIDs {
            guard let row = node(id), let hook = deletionHook(of: row) else { continue }
            let key = ObjectIdentifier(hook.box)
            if offsets[key] == nil { order.append(hook.box) }
            offsets[key, default: []].append(hook.offset)
        }
        for box in order {
            box.perform(IndexSet(offsets[ObjectIdentifier(box)] ?? []))
        }
        return !order.isEmpty
    }

    /// Deletes a single row through its `onDelete` handler (swipe or context-menu delete in a backend).
    @discardableResult
    public func deleteRow(_ rowID: String) -> Bool {
        deleteRows([rowID])
    }

    /// Deletes the selected rows of a List (the Delete key). macOS and Windows list deletion from the keyboard is
    /// a backend choice; this hook provides the model side.
    @discardableResult
    public func deleteSelection(in listID: String) -> Bool {
        guard let list = node(listID), let access = list.selection else { return false }
        let selected = access.current()
        return deleteRows(taggedRows(of: list).filter { selected.contains($0.tag) }.map { $0.node.id.description })
    }

    // MARK: Helpers

    /// The tag of a row: a `.tag` modifier reached through single-child wrappers.
    func tagOf(_ node: Node) -> AnyHashable? {
        if case .modifier(.tag(let tag)) = node.kind { return tag }
        guard node.kind.passesThrough else { return nil }
        let children = childNodes(node)
        return children.count == 1 ? tagOf(children[0]) : nil
    }

    /// The `onDelete` hook of a row, reached through single-child wrappers.
    func deletionHook(of node: Node) -> DeletionHook? {
        if case .modifier(.deletion(let hook)) = node.kind { return hook }
        guard node.kind.passesThrough else { return nil }
        let children = childNodes(node)
        return children.count == 1 ? deletionHook(of: children[0]) : nil
    }

    /// The tagged children of a List, in order.
    func taggedRows(of list: Node) -> [(tag: AnyHashable, node: Node)] {
        childNodes(list).compactMap { child in
            tagOf(child).map { (tag: $0, node: child) }
        }
    }

    /// The nearest ancestor that owns a selection binding.
    private func selectionOwner(of row: Node) -> Node? {
        var current = row.parent
        while let candidate = current {
            if candidate.selection != nil { return candidate }
            current = candidate.parent
        }
        return nil
    }
}
