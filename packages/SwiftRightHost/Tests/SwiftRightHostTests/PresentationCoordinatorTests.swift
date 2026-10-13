import XCTest
import SwiftRightHost
import SwiftRightBridge
import Observation

private func a(_ title: String, _ role: ButtonRole? = nil) -> ResolvedPresentationAction { ResolvedPresentationAction(title: title, role: role, isDisabled: false) }
private func layout(_ kind: String, _ actions: [ResolvedPresentationAction]) -> String {
    DialogLayout.buttons(kind: kind, actions: actions).map { ($0.isDefault ? "*" : "") + $0.title + ($0.sourceIndex == nil ? "+" : "") }.joined(separator: ",")
}

@Observable @MainActor private final class Model { var presented = true; var outcome = "none" }
private struct Screen: View {
    @Bindable var model: Model
    var body: some View {
        Text("x").frame(width: 10, height: 10)
            .alert("Delete?", isPresented: $model.presented) {
                Button("Delete", role: .destructive) { model.outcome = "delete" }
                Button("Cancel", role: .cancel) { model.outcome = "cancel" }
            } message: { Text("Gone for good.") }
    }
}

/// The rows of the macOS matrix measured from the NSAlert SwiftUI builds (probe over twenty-one variants; factory/pipeline/blocks-17-20/README.md).
final class DialogLayoutTests: XCTestCase {
    func testMeasuredMacOSMatrix() {
        XCTAssertEqual(layout("alert", [a("OK")]), "*OK")
        XCTAssertEqual(layout("alert", []), "*OK+")
        XCTAssertEqual(layout("alert", [a("Delete", .destructive), a("Cancel", .cancel)]), "Delete,Cancel")
        XCTAssertEqual(layout("alert", [a("Cancel", .cancel), a("Delete", .destructive)]), "Delete,Cancel")
        XCTAssertEqual(layout("alert", [a("A"), a("Cancel", .cancel), a("B")]), "*A,Cancel,B")
        XCTAssertEqual(layout("alert", [a("A"), a("B"), a("C")]), "*A,B,C")
        XCTAssertEqual(layout("confirmationDialog", [a("A"), a("B")]), "*A,B,Cancel+")
        XCTAssertEqual(layout("confirmationDialog", [a("A"), a("B", .destructive)]), "*A,B,Cancel+")
        XCTAssertEqual(layout("alert", [a("Cancel", .cancel), a("A"), a("B")]), "Cancel,A,B")
        XCTAssertEqual(layout("alert", [a("Cancel", .cancel), a("A")]), "*A,Cancel")
        XCTAssertEqual(layout("alert", [a("Delete", .destructive), a("A")]), "Delete,A,Cancel+")
        XCTAssertEqual(layout("alert", [a("Never mind", .cancel)]), "Never mind")
        XCTAssertEqual(layout("alert", [a("A"), a("B", .destructive), a("Cancel", .cancel)]), "*A,B,Cancel")
        XCTAssertEqual(layout("confirmationDialog", [a("Never mind", .cancel), a("A")]), "*A,Never mind")
    }
}

@MainActor
final class PresentationCoordinatorTests: XCTestCase {
    private struct Request { let id: UInt64; let title: String; let message: String; let buttons: [String]; let defaultIndex: Int }

    private func make(_ model: Model) -> (Graph, PresentationCoordinator, () -> [Request]) {
        let graph = Graph(Screen(model: model))
        graph.flush()
        var requests: [Request] = []
        let coordinator = PresentationCoordinator(graph: graph, present: { id, title, message, items, d in
            requests.append(Request(id: id, title: title, message: message, buttons: items.map(\.text), defaultIndex: d))
        }, log: { _ in })
        return (graph, coordinator, { requests })
    }

    private func answer(_ id: UInt64, index: Int?) -> BridgeEvent {
        BridgeEvent(kindRaw: BridgeEvent.Kind.modalResult.rawValue, action: 3, window: 0, node: 0, snapshot: 0, seq: 0, arg: id, x: 0, y: 0,
                    i0: index.map { Int32($0 + 1) } ?? 0, i1: Int32(index ?? -1), modifiers: 0, text: "", typed: "")
    }

    func testPresentedAlertIsRequestedOnceWithTitleMessageAndButtons() throws {
        let model = Model()
        let (graph, coordinator, requests) = make(model)
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertEqual(requests().count, 1, "one dialog per presentation")
        XCTAssertEqual(requests()[0].title, "Delete?")
        XCTAssertEqual(requests()[0].message, "Gone for good.")
        XCTAssertEqual(requests()[0].buttons, ["Delete", "Cancel"])
        XCTAssertEqual(requests()[0].defaultIndex, 1, "no default button: the safe (cancel) one is the dialog's default")
    }

    func testButtonRunsItsActionAndDismisses() throws {
        let model = Model()
        let (graph, coordinator, requests) = make(model)
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertTrue(coordinator.handle(answer(requests()[0].id, index: 0)))
        XCTAssertEqual(model.outcome, "delete")
        XCTAssertFalse(model.presented, "the binding is reset on dismiss")
        graph.flush()
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertEqual(requests().count, 1, "a dismissed presentation is not asked for again")
        XCTAssertEqual(coordinator.openDialogs, 0)
    }

    func testClosingTheDialogRunsTheCancelAction() throws {
        let model = Model()
        let (graph, coordinator, requests) = make(model)
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertTrue(coordinator.handle(answer(requests()[0].id, index: nil)))
        XCTAssertEqual(model.outcome, "cancel")
        XCTAssertFalse(model.presented)
    }

    func testRepresentingAfterDismissOpensANewDialog() throws {
        let model = Model()
        let (graph, coordinator, requests) = make(model)
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        coordinator.handle(answer(requests()[0].id, index: 1))
        graph.flush()
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        model.presented = true
        graph.flush()
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertEqual(requests().count, 2)
        XCTAssertNotEqual(requests()[0].id, requests()[1].id)
    }

    func testAnswerToAnotherRequestIsNotOurs() throws {
        let model = Model()
        let (graph, coordinator, _) = make(model)
        try coordinator.sync(root: try XCTUnwrap(graph.snapshot()))
        XCTAssertFalse(coordinator.handle(answer(999, index: 0)))
        XCTAssertTrue(model.presented)
    }
}
