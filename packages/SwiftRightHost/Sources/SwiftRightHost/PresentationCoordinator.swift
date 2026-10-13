import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// One button of a presented alert or confirmation dialog as the host shows it. SwiftUI on macOS decides the order, the default button and the
/// buttons it adds itself (measured from the NSAlert SwiftUI builds, factory/pipeline/blocks-17-20/README.md); `sourceIndex` is the position of the
/// action in the runtime's presentation model (`Graph.performPresentationAction`), nil for a button the platform added.
public struct DialogButton: Equatable {
    public var title: String
    public var role: ButtonRole?
    public var isDefault: Bool
    public var isDisabled: Bool
    public var sourceIndex: Int?
}

public enum DialogLayout {
    /// The macOS rules, as measured:
    ///  - an alert without actions gets one default "OK";
    ///  - an alert that has a destructive action but no cancel action, and every confirmation dialog without a cancel action, gets a "Cancel";
    ///  - with exactly two buttons of which the first is the cancel button, the cancel button goes last; with more, the order is the source order;
    ///  - the first button is the default (Return) unless it is a cancel or a destructive one; then there is no default.
    public static func buttons(kind: String, actions: [ResolvedPresentationAction]) -> [DialogButton] {
        var out: [DialogButton] = actions.enumerated().map { DialogButton(title: $0.element.title, role: $0.element.role, isDefault: false, isDisabled: $0.element.isDisabled, sourceIndex: $0.offset) }
        let hasCancel = out.contains { $0.role == .cancel }
        let hasDestructive = out.contains { $0.role == .destructive }
        if out.isEmpty && kind == "alert" {
            out = [DialogButton(title: "OK", role: nil, isDefault: false, isDisabled: false, sourceIndex: nil)]
        } else if !hasCancel && (kind == "confirmationDialog" || hasDestructive) {
            out.append(DialogButton(title: "Cancel", role: .cancel, isDefault: false, isDisabled: false, sourceIndex: nil))
        }
        if out.count == 2, out[0].role == .cancel, out[1].role != .cancel { out.swapAt(0, 1) }
        if let first = out.first, first.role == nil { out[0].isDefault = true }
        return out
    }
}

/// Shows the runtime's presented alerts and confirmation dialogs through the renderer's modal dialog (SWR_MODAL_DIALOG, a Windows TaskDialog) and routes the
/// answer back: a button runs its action and dismisses (`Graph.performPresentationAction`), a button the platform added or a closed dialog dismisses
/// (`Graph.dismissPresentation`), and closing a dialog that has a cancel button runs that button's action, as Escape does on macOS.
/// The host calls `sync(root:)` after each commit and `handle(_:)` for each bridge event, then flushes the graph.
@MainActor
public final class PresentationCoordinator {
    public typealias Present = (_ requestID: UInt64, _ title: String, _ message: String, _ buttons: [BridgeWindow.ModalItem], _ defaultIndex: Int) throws -> Void

    struct Active { let nodeID: String; let buttons: [DialogButton] }
    private let graph: Graph
    private let present: Present
    private let log: (String) -> Void
    private var nextRequest: UInt64 = 1
    private var active: [UInt64: Active] = [:]
    /// Presentations whose binding went false while their dialog was open (the ABI cannot close a dialog; the answer is ignored).
    public private(set) var staleRequests: Set<UInt64> = []

    public init(graph: Graph, present: @escaping Present, log: @escaping (String) -> Void = { print($0) }) {
        self.graph = graph; self.present = present; self.log = log
    }

    /// Requests a dialog for every node that presents one and has none open; marks the dialogs of presentations that ended.
    public func sync(root: ResolvedNode) throws {
        var presented: [String: ResolvedPresentation] = [:]
        func walk(_ n: ResolvedNode) { if let p = n.presentation { presented[n.id] = p }; n.children.forEach(walk) }
        walk(root)
        for (id, request) in active where presented[request.nodeID] == nil && !staleRequests.contains(id) { staleRequests.insert(id) }
        let open = Set(active.values.map(\.nodeID))
        for nodeID in presented.keys.sorted() where !open.contains(nodeID) {
            let p = presented[nodeID]!
            let buttons = DialogLayout.buttons(kind: p.kind, actions: p.actions)
            let id = nextRequest; nextRequest += 1
            active[id] = Active(nodeID: nodeID, buttons: buttons)
            let items = buttons.enumerated().map { BridgeWindow.ModalItem(id: UInt32($0.offset + 1), text: $0.element.title, disabled: false) }
            let defaultIndex = buttons.firstIndex { $0.isDefault } ?? buttons.firstIndex { $0.role == .cancel } ?? 0
            log("HOST_DIALOG_REQUEST id=\(id) node=\(nodeID) kind=\(p.kind) title=\(p.title) buttons=\(buttons.map(\.title).joined(separator: "|")) default=\(defaultIndex)")
            try present(id, p.title, p.message ?? "", items, defaultIndex)
        }
    }

    /// True when the event was the answer to one of this coordinator's dialogs (the graph was updated; flush it).
    @discardableResult
    public func handle(_ event: BridgeEvent) -> Bool {
        guard event.kind == .modalResult, event.action == 3, let request = active.removeValue(forKey: event.arg) else { return false }
        if staleRequests.remove(event.arg) != nil { log("HOST_DIALOG_ANSWER id=\(event.arg) ignored (presentation already ended)"); return true }
        if event.modalFailed { log("HOST_DIALOG_FAILED id=\(event.arg)"); _ = graph.dismissPresentation(request.nodeID); return true }
        let chosen: DialogButton?
        if let choice = event.modalChoice, request.buttons.indices.contains(choice.index) { chosen = request.buttons[choice.index] }
        else { chosen = request.buttons.first { $0.role == .cancel } }   // closed without a button: Escape / the close box
        if let source = chosen?.sourceIndex { _ = graph.performPresentationAction(request.nodeID, index: source) } else { _ = graph.dismissPresentation(request.nodeID) }
        log("HOST_DIALOG_ANSWER id=\(event.arg) button=\(chosen?.title ?? "-") sourceIndex=\(chosen?.sourceIndex.map(String.init) ?? "-")")
        return true
    }

    public var openDialogs: Int { active.count }
}
