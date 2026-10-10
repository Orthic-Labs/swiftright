import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// SR1 controls: Toggle, Image, TextEditor, Label, Divider, style values, disabled, accessibility.
// Apple references for the behaviour under test are cited in the runtime sources.

@MainActor
func sr1All(_ root: ResolvedNode?) -> [ResolvedNode] {
    guard let root else { return [] }
    var out: [ResolvedNode] = []
    func walk(_ node: ResolvedNode) {
        out.append(node)
        node.children.forEach(walk)
    }
    walk(root)
    return out
}

@MainActor
func sr1Kind(_ graph: Graph, _ kind: String) -> [ResolvedNode] {
    sr1All(graph.snapshot()).filter { $0.kind == kind }
}

@MainActor
func sr1Node(_ graph: Graph, _ id: String) -> ResolvedNode? {
    sr1All(graph.snapshot()).first { $0.id == id }
}

@Observable
@MainActor
final class SR1Flags {
    var wifi = false
    var alt = false
    var logo = ""
    var note = ""
    var title = ""
}

struct SR1ToggleScreen: View {
    @Bindable var model: SR1Flags

    var body: some View {
        VStack {
            Toggle("Wi-Fi", isOn: $model.wifi)
            Toggle(isOn: $model.alt) { Text("Alt") }
                .disabled(true)
        }
    }
}

struct SR1ImageScreen: View {
    var body: some View {
        VStack {
            Image(systemName: "star.fill")
            Image("logo").accessibilityLabel("Company logo")
        }
    }
}

struct SR1EditorScreen: View {
    @Bindable var model: SR1Flags

    var body: some View {
        VStack {
            TextEditor(text: $model.note)
            TextField("Title", text: $model.title)
        }
    }
}

struct SR1LabelScreen: View {
    var body: some View {
        VStack {
            Label("Inbox", systemImage: "tray")
            Divider()
            HStack {
                Divider()
                Text("x")
            }
            .font(.title)
            .foregroundStyle(.red)
        }
    }
}

@Observable
@MainActor
final class SR1Counter {
    var a = 0
    var b = 0
    var c = 0
    var d = 0
}

struct SR1DisabledScreen: View {
    @Bindable var model: SR1Counter

    var body: some View {
        VStack {
            Button("A") { model.a += 1 }
                .disabled(true)
            VStack {
                Button("B") { model.b += 1 }
            }
            .disabled(true)
            .disabled(false)
            Button("C") { model.c += 1 }
        }
    }
}

@MainActor
final class SR1ControlTests: XCTestCase {

    // Toggle(_:isOn:) flips its binding through the runtime, and reports checkbox role and 0/1 value.
    // https://developer.apple.com/documentation/swiftui/toggle
    func testToggleFlipsBindingAndReportsCheckboxState() {
        let model = SR1Flags()
        let graph = Graph(SR1ToggleScreen(model: model))
        graph.flush()
        let toggles = graph.ids(ofKind: "Toggle")
        XCTAssertEqual(toggles.count, 2)

        let wifi = sr1Node(graph, toggles[0])
        XCTAssertEqual(wifi?.accessibility.role, "checkbox")
        XCTAssertEqual(wifi?.accessibility.label, "Wi-Fi")
        XCTAssertEqual(wifi?.accessibility.value, "0")
        XCTAssertEqual(wifi?.accessibility.isEnabled, true)

        XCTAssertTrue(graph.activateToggle(toggles[0]))
        XCTAssertTrue(model.wifi)
        graph.flush()
        XCTAssertEqual(sr1Node(graph, toggles[0])?.accessibility.value, "1")
    }

    // A disabled toggle does not flip, and reports disabled accessibility state.
    func testDisabledToggleDoesNotFlip() {
        let model = SR1Flags()
        let graph = Graph(SR1ToggleScreen(model: model))
        graph.flush()
        let alt = graph.ids(ofKind: "Toggle")[1]
        XCTAssertFalse(graph.activateToggle(alt))
        XCTAssertFalse(model.alt)
        XCTAssertEqual(sr1Node(graph, alt)?.accessibility.isEnabled, false)
        XCTAssertEqual(sr1Node(graph, alt)?.accessibility.label, "Alt")
    }

    // Image(systemName:) and Image(_:) are resolved references with accessibility labels. A modifier overrides
    // the label of its own node. The host supplies intrinsic sizes.
    // https://developer.apple.com/documentation/swiftui/image
    func testImageReferencesAndLabels() {
        let graph = Graph(SR1ImageScreen())
        graph.flush()
        let images = sr1Kind(graph, "Image")
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].image, .system("star.fill"))
        XCTAssertEqual(images[0].accessibility.role, "image")
        XCTAssertEqual(images[0].accessibility.label, "star.fill")
        XCTAssertEqual(images[1].image, .named("logo"))
        XCTAssertEqual(images[1].accessibility.label, "logo")

        let override = sr1Kind(graph, "modifier.accessibilityLabel")
        XCTAssertEqual(override.first?.accessibility.label, "Company logo")
    }

    func testImageUsesHostIntrinsicSize() {
        let graph = Graph(SR1ImageScreen())
        graph.imageIntrinsicSize = { _ in LayoutSize(width: 40, height: 12) }
        graph.flush()
        let first = sr1Kind(graph, "Image").first
        XCTAssertEqual(first?.frame.width, 40)
        XCTAssertEqual(first?.frame.height, 12)
    }

    // TextEditor is multi-line over the shared TextInputState model: Return inserts a line break, the height
    // grows with the lines, and the field role is text-area.
    // https://developer.apple.com/documentation/swiftui/texteditor
    func testTextEditorInsertsLineBreaksAndMeasuresLines() {
        let model = SR1Flags()
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(SR1EditorScreen(model: model), measurer: measurer)
        graph.flush()
        let editor = graph.ids(ofKind: "TextEditor")[0]
        let input = graph.textInput(editor)!
        XCTAssertTrue(input.multiline)

        input.replace(text: "ab")
        XCTAssertTrue(input.insertLineBreak())
        input.replace(text: "cd")
        XCTAssertEqual(model.note, "ab\ncd")
        graph.flush()

        let node = sr1Node(graph, editor)
        XCTAssertEqual(node?.accessibility.role, "text-area")
        XCTAssertEqual(node?.accessibility.value, "ab\ncd")
        XCTAssertEqual(node?.frame.height, 32, "two lines at 16 pt")
    }

    // Return in a single-line TextField inserts nothing. While composing, Return commits the composition
    // instead of inserting a line break, as an IME does.
    func testReturnCommitsCompositionAndSingleLineRejectsBreaks() {
        let model = SR1Flags()
        let graph = Graph(SR1EditorScreen(model: model))
        graph.flush()
        let field = graph.ids(ofKind: "TextField")[0]
        let fieldInput = graph.textInput(field)!
        XCTAssertFalse(fieldInput.insertLineBreak())
        XCTAssertEqual(model.title, "")

        let editor = graph.textInput(graph.ids(ofKind: "TextEditor")[0])!
        editor.replace(text: "ab")
        editor.replaceAndMark(text: "ni")
        XCTAssertEqual(editor.display, "abni")
        XCTAssertTrue(editor.insertLineBreak())
        XCTAssertNil(editor.markedRange)
        XCTAssertEqual(model.note, "abni", "composition committed, no newline inserted")
    }

    // Label keeps icon then title; Divider is a 1-point line across its stack; style values reach the text
    // node through the environment, and the measurer receives the font identifier.
    // https://developer.apple.com/documentation/swiftui/label
    // https://developer.apple.com/documentation/swiftui/divider
    func testLabelDividerAndStyleResolve() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(SR1LabelScreen(), measurer: measurer)
        graph.flush()

        let label = sr1Kind(graph, "Label")
        XCTAssertEqual(label.count, 1)
        XCTAssertEqual(label[0].children.map(\.kind), ["Image", "Text"])
        XCTAssertEqual(label[0].children.last?.text, "Inbox")

        let dividers = sr1Kind(graph, "Divider")
        XCTAssertEqual(dividers.count, 2)
        XCTAssertEqual(dividers[0].frame.height, 1, "vertical stack: thin on the main axis")
        XCTAssertEqual(dividers[1].frame.width, 1, "horizontal stack: thin on the main axis")

        let styled = sr1Kind(graph, "Text").first { $0.text == "x" }
        XCTAssertEqual(styled?.style.font, .title)
        XCTAssertEqual(styled?.style.foreground, .semantic("system.red"))
        XCTAssertTrue(measurer.requests.contains { $0.text == "x" && $0.fontID == "textStyle.title" })
    }

    // `.disabled` applies to the subtree and cannot be undone by a nested `.disabled(false)`.
    // Disabled buttons do not fire and report isEnabled false.
    // https://developer.apple.com/documentation/swiftui/view/disabled(_:)
    func testDisabledBlocksButtonsAndNestedFalseDoesNotReenable() {
        let model = SR1Counter()
        let graph = Graph(SR1DisabledScreen(model: model))
        graph.flush()
        let buttons = graph.ids(ofKind: "Button")
        XCTAssertEqual(buttons.count, 3)

        XCTAssertFalse(graph.tapButton(buttons[0]))
        XCTAssertFalse(graph.tapButton(buttons[1]))
        XCTAssertTrue(graph.tapButton(buttons[2]))
        XCTAssertEqual(model.a, 0)
        XCTAssertEqual(model.b, 0)
        XCTAssertEqual(model.c, 1)

        graph.flush()
        XCTAssertEqual(sr1Node(graph, buttons[0])?.accessibility.isEnabled, false)
        XCTAssertEqual(sr1Node(graph, buttons[0])?.accessibility.role, "button")
        XCTAssertEqual(sr1Node(graph, buttons[0])?.accessibility.label, "A")
    }
}
