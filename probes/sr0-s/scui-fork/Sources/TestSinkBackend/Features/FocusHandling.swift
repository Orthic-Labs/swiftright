@_spi(Backends) import SwiftCrossUI

// SR0-S sink: minimal focus model. Only text fields are focusable (buttons are not keyboard-focusable by default on macOS); the last
// `.focused` request in a commit wins, as with a real toolkit's focus chain.
extension DummyBackend: BackendFeatures.FocusHandling {
    public func registerFocusObservers(_ data: [WidgetFocusObserver], on widget: Widget) {
        focusObservers[ObjectIdentifier(widget)] = data
    }

    public func setFocusEffectDisabled(on widget: Widget, disabled: Bool) {}

    public func setFocus(of widget: Widget, to focus: SwiftCrossUI.Focus) {
        guard widget is TextField else { return }
        switch focus {
            case .focused:
                if focusedWidget !== widget { userFocus(widget) }
            case .unfocused:
                if focusedWidget === widget { userBlur() }
        }
    }

    /// Simulates the user (or toolkit) moving focus to `widget`.
    public func userFocus(_ widget: Widget) {
        if let old = focusedWidget, old !== widget {
            focusedWidget = nil
            for observer in focusObservers[ObjectIdentifier(old)] ?? [] { observer.didLoseFocus() }
        }
        focusedWidget = widget
        for observer in focusObservers[ObjectIdentifier(widget)] ?? [] { observer.didGainFocus() }
    }

    public func userBlur() {
        guard let old = focusedWidget else { return }
        focusedWidget = nil
        for observer in focusObservers[ObjectIdentifier(old)] ?? [] { observer.didLoseFocus() }
    }
}
