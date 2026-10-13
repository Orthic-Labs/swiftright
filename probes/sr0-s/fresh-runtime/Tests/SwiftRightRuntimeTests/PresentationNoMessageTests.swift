import SwiftRightRuntime
import XCTest

@Observable
@MainActor
private final class NoMessageModel { var shown = true; var picked = "" }

private struct NoMessageScreen: View {
    @Bindable var model: NoMessageModel
    var body: some View {
        Text("Body")
            .confirmationDialog("Share", isPresented: $model.shown) {
                Button("Copy link") { model.picked = "copy" }
                Button("Email") { model.picked = "email" }
            }
    }
}

private struct NoMessageAlert: View {
    @Bindable var model: NoMessageModel
    var body: some View {
        Text("Body").alert("Heads up", isPresented: $model.shown) { Button("OK") { model.picked = "ok" } }
    }
}

/// The message-less overloads of `.alert` and `.confirmationDialog` present with a nil message and dispatch like the others.
@MainActor
final class PresentationNoMessageTests: XCTestCase {
    func testConfirmationDialogWithoutMessage() throws {
        let model = NoMessageModel()
        let graph = Graph(NoMessageScreen(model: model))
        graph.flush()
        let node = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "modifier.confirmationDialog" })
        XCTAssertEqual(node.presentation?.title, "Share")
        XCTAssertNil(node.presentation?.message)
        XCTAssertEqual(node.presentation?.titleVisibility, .automatic)
        XCTAssertEqual(node.presentation?.actions.map(\.title), ["Copy link", "Email"])
        XCTAssertTrue(graph.performPresentationAction(node.id, index: 1))
        XCTAssertEqual(model.picked, "email")
        XCTAssertFalse(model.shown)
    }

    func testAlertWithoutMessage() throws {
        let model = NoMessageModel()
        let graph = Graph(NoMessageAlert(model: model))
        graph.flush()
        let node = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "modifier.alert" })
        XCTAssertEqual(node.presentation?.title, "Heads up")
        XCTAssertNil(node.presentation?.message)
        XCTAssertTrue(graph.performPresentationAction(node.id, index: 0))
        XCTAssertEqual(model.picked, "ok")
    }
}
