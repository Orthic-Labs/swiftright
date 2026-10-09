import Foundation
#if os(macOS)
import SwiftUI

// macOS bootstrap: a minimal SwiftUI App with one Window. The shared screen is the only root.
@main
struct SliceAppMain: App {
    @State private var model: EditorModel

    init() {
        let store = SliceAppData.rowsURL().map { RowStore(url: $0) }
        _model = State(initialValue: EditorModel(store: store))
    }

    var body: some Scene {
        Window("SliceApp", id: "main") {
            EditorScreen(model: model)
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}
#else

// Windows bootstrap entry. Synchronous on the initial thread (the bridge requires it); the work lives in
// sliceAppWindowsMain (Windows/WindowsBootstrap.swift). Exit codes: see that function.
@main
enum SliceAppMain {
    static func main() {
        let status = MainActor.assumeIsolated { sliceAppWindowsMain() }
        fflush(stdout)
        exit(status)
    }
}
#endif
